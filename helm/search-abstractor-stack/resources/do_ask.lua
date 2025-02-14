--[[

    Copyright 2024-2025 Open Text.

    The only warranties for products and services of Open Text and its
    affiliates and licensors ("Open Text") are as may be set forth in the
    express warranty statements accompanying such products and services.
    Nothing herein should be construed as constituting an additional
    warranty. Open Text shall not be liable for technical or editorial
    errors or omissions contained herein. The information contained herein
    is subject to change without notice.

    Except as specifically indicated otherwise, this document contains
    confidential information and a valid license is required for possession,
    use or copying. If this work is provided to the U.S. Government,
    consistent with FAR 12.211 and 12.212, Commercial Computer Software,
    Computer Software Documentation, and Technical Data for Commercial Items
    are licensed to the U.S. Government under vendor's standard commercial
    license.

]]
local config_string =
[===[
[http]
ProxyHost=
ProxyPort=
]===]
local config = LuaConfig:new(config_string)
local RAG_TYPE_NAME = "rag"


local function sendIDOLAction(idolServerHost, idolServerPort, timeout, action, params)
    
    local response = send_aci_action(idolServerHost, idolServerPort, action, params, timeout)
    log_info("IDOL Response:", response)

    local responseXml = nil
    if response ~= nil then
        responseXml = parse_xml(response)
        responseXml:XPathRegisterNs("autn", "http://schemas.autonomy.com/aci/") 
    end
    
    return responseXml
end

local function sendAskAction(idolServerHost, idolServerPort, timeout, securityInfo, text, system, sessionInfo, matchReferences, parametricFilters)

    local params = {SystemNames = system, text = text}

    if matchReferences ~= nil and matchReferences ~= "" then
        params.matchreference = matchReferences
    end

    if parametricFilters ~= nil and parametricFilters ~= "" then
        params.fieldtext = parametricFilters
    end

    local customData = LuaJsonArray:new()
    for _, sys in ipairs({"RAGPassageExtractor", "LLMPassageExtractor"}) do
        customData:append(LuaJsonObject:new({
            ["system_name"] = sys, ["security_info"] = securityInfo
        }))
    end
    if sessionInfo ~= nil then
        customData:append(LuaJsonObject:new({
            ["system_name"] = "global", ["session_data"] = sessionInfo
        }))
    end

    params.CustomizationData = customData:string()
    
    return sendIDOLAction(idolServerHost, idolServerPort, timeout, "ask", params)
end


local function splitOn(inputStr, separator)
    local elements = {}
    for element in string.gmatch(inputStr, "([^" .. separator .. "]+)") do
        table.insert(elements, element)
    end
    return elements
end

local function getMatchReferences(refs)
    local allRefs = splitOn(refs, ",")
    local escapedRefs = {}
    for _, ref in ipairs(allRefs) do
        local thisRef = string.gsub(ref, "%%2C", ",")
        table.insert(escapedRefs, url_escape(thisRef))
    end

    return table.concat(escapedRefs, "+")
end

local function getAnswer(idolServerHost, idolServerPort, timeout, securityInfo, input, system, docListField, sessionInfo, matchReferences, parametricFilters)
    local responseXml = sendAskAction(idolServerHost, idolServerPort, timeout, securityInfo, input, system, sessionInfo, matchReferences, parametricFilters)
    if responseXml ~= nil then
        local answersNodeSet = responseXml:XPathExecute("//responsedata/answers/answer")

        for _, answerNode in answersNodeSet:ipairs() do
            local text = responseXml:XPathValue("text", answerNode)
            local score = responseXml:XPathValue("score", answerNode)

            local documentField = docListField:addChild("IDOLDoc")
            documentField:addChild("text"):setValue(text)
            documentField:addChild("score"):setValue(score)

            if (responseXml:XPathValue("//responsedata/answers/answer/@answer_type") == RAG_TYPE_NAME) then
                local sourcesNodeSet = responseXml:XPathExecute("metadata/sources/source", answerNode)
                if sourcesNodeSet ~= nil then
                    for i, sourceNode in sourcesNodeSet:ipairs() do
                        documentField:addChild("source_" .. i):setValue(responseXml:XPathValue("@ref", sourceNode))
                        documentField:addChild("title_" .. i):setValue(responseXml:XPathValue("@title", sourceNode))
                        documentField:addChild("database_" .. i):setValue(responseXml:XPathValue("@database", sourceNode))
                        local source_text = responseXml:XPathValue("text", sourceNode)
                        if source_text ~= nil then
                            documentField:addChild("paragraph_" .. i):setValue(source_text)
                        end
                    end
                end
            else
                local source = responseXml:XPathValue("source", answerNode)
                local paragraph = responseXml:XPathValue("metadata/paragraph", answerNode)
                documentField:addChild("source"):setValue(source)
                if paragraph ~= nil then
                    documentField:addChild("paragraph"):setValue(paragraph)
                end
            end
            --only care about the first answer
            return true
        end
    end
    
    return false
end

local function getSessionData(sessionBackend, sessionInfoURL, sessionMaxSteps)

    local url = string.format("%s%s?sortSteps=REVERSEDATE&maxSteps=%d", sessionBackend, sessionInfoURL, sessionMaxSteps)
    local request = LuaHttpRequest:new(config, "http")

    request:set_url(url)

    local response = request:send()
    local content = response:get_body()

    log_info("Session Request:", url)
    log_info("Session Response:", content)

    local session_obj = parse_json_object(content)
    if session_obj == nil then
        -- no session data, so don't use it
        return nil, nil
    end

    local steps = session_obj:lookup("steps")
    if steps == nil or #steps:array() == 0 then
        return nil, nil
    end

    local history = LuaJsonArray:new()

    for i = #steps:array()-1, 0, -1 do
        local step_obj = steps:array():lookup(i):object()
        if step_obj:lookup("status"):value() == "success" then
            local question = step_obj:lookup("input"):value()
            local answer = step_obj:lookup("response"):value()
            history:append(LuaJsonObject:new({["question"] = question,
                                                ["answer"] = answer}))
        end
    end

    return history:string()
end

function handler(ffdocument, session)

    local securityInfo = ffdocument:getAttribute("idol.securityinfo")
    local sessionInfoURL = ffdocument:getAttribute("idol.sessioninfo.url", "")
    local idolServerHost = session:evaluateAttributeExpressions(session:getProperty("IDOLServerHost"))
    local idolServerPort = session:evaluateAttributeExpressions(session:getProperty("IDOLServerPort"))
    local large_timeout = tonumber(session:getProperty("ACIServerTimeoutLarge"))
    local small_timeout = tonumber(session:getProperty("ACIServerTimeoutSmall"))
    local sessionBackend = session:evaluateAttributeExpressions(session:getProperty("SessionBackend"))
    local sessionMaxSteps = session:evaluateAttributeExpressions(session:getProperty("SessionMaxSteps"))
    local systemOrderCSV = session:evaluateAttributeExpressions(session:getProperty("SystemPreferenceOrder"))
    local systemOrder = splitOn(systemOrderCSV, ",")
    local matchReferences = getMatchReferences(ffdocument:getAttribute("idol.matchreferences", ""))
    local parametricFilters = ffdocument:getAttribute("idol.parametricfilters", "")

    log_info("IDOL Server Host:", idolServerHost)
    log_info("IDOL Server Port:", idolServerPort)

    ffdocument:setAttribute("routepath", "idol.ask")

    local sessionInfo = nil
    if sessionInfoURL ~= "" then
        sessionInfo = getSessionData(sessionBackend, sessionInfoURL, sessionMaxSteps)
    end

    --Protected call, to ensure we destroy the context regardless of what happens below
    local status, retval = pcall(ffdocument.modify, ffdocument, {
        onContent =
            function(action)
                action:readContent(
                    function(inputstream)
                        local content = inputstream:read("a")
                        local docListField = action:getXmlMetadata():addChild("IDOLDocList")

                        for _, system in ipairs(systemOrder) do
                            log_info(string.format("Trying answer system %s to find answer...", system))
                            if getAnswer(idolServerHost, idolServerPort, large_timeout, securityInfo, string.sub(content, 1, 2000),
                                        system, docListField, sessionInfo, matchReferences, parametricFilters) then
                                log_info(string.format("Answer system %s produced answer.", system))
                                break
                            end
                        end
                    end
                )
                action:deletePart()
            end
    })

    if not status then
        error(retval)
    end

end 
