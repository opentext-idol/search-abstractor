local config_string =
[===[
[http]
ProxyHost=
ProxyPort=
]===]
local config = LuaConfig:new(config_string)
local RAG_TYPE_NAME = "rag"


local function sendIDOLAction(url, body)

    local request = LuaHttpRequest:new(config, "http")

    request:set_url(url)

    if body ~= nil then
        request:set_body(body)
        request:set_method("POST")
    end

    local response = request:send()

    log_info("IDOL Request:", url)
    log_info("IDOL Response:", response:get_body())

    local responseXml = parse_xml(response:get_body())
    responseXml:XPathRegisterNs("autn", "http://schemas.autonomy.com/aci/")

    return responseXml
end

local function sendAskAction(idolServer, securityInfo, text, system, sessionInfo, contextId, matchReferences, parametricFilters)

    local askURL = idolServer
        .. "?action=Ask"
        .. "&SecurityInfo=" .. url_escape(securityInfo)
        .. "&SystemNames=" .. url_escape(system)
        .. "&text=" .. url_escape(text)

    if matchReferences ~= nil and matchReferences ~= "" then
        askURL = askURL .. "&matchreference=" .. matchReferences
    end

    if parametricFilters ~= nil and parametricFilters ~= "" then
        askURL = askURL .. "&fieldtext=" .. parametricFilters
    end

    if contextId ~= nil then
        askURL = askURL .. "&context=" .. contextId
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

    return sendIDOLAction(askURL, "CustomizationData=" .. url_escape(customData:string()))
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

    return url_escape(table.concat(escapedRefs, "+"))
end

local function getAnswer(idolServer, securityInfo, input, system, docListField, sessionInfo, contextId, matchReferences, parametricFilters)
    local responseXml = sendAskAction(idolServer, securityInfo, input, system, sessionInfo, contextId, matchReferences, parametricFilters)
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
    local last_answer = nil

    for i = #steps:array()-1, 0, -1 do
        local step_obj = steps:array():lookup(i):object()
        if step_obj:lookup("status"):value() == "success" then
            local question = step_obj:lookup("input"):value()
            local answer = step_obj:lookup("response"):value()
            history:append(LuaJsonObject:new({["question"] = question,
                                                ["answer"] = answer}))
            last_answer = answer
        end
    end

    return history:string(), last_answer
end

local function makeContext(idolServer, contextData, system)
    local context = LuaJsonArray:new()
    context:append(contextData)
    local data_obj = LuaJsonObject:new({["context"] = context})
    local context_obj = LuaJsonObject:new({["system_name"] = system, ["data"] = data_obj})
    local context_arr =  LuaJsonArray:new()
    context_arr:append(context_obj)
    local to_send_obj = LuaJsonObject:new({["operation"] = "add", ["type"] = "context", ["context"] = context_arr})

    local url = idolServer
                .. "?action=manageResources"
                .. "&data=" .. base64_encode(to_send_obj:string())

    local request = LuaHttpRequest:new(config, "http")

    request:set_url(url)

    local response = request:send()

    log_info("IDOL Request:", url)
    log_info("IDOL Response:", response:get_body())

    local responseXml = parse_xml(response:get_body())
    responseXml:XPathRegisterNs("autn", "http://schemas.autonomy.com/aci/")

    return responseXml:XPathValue("//responsedata/result/managed_resources/id")
end

local function destroyContext(idolServer, contextId)
    local to_send_obj = LuaJsonObject:new({["operation"] = "delete", ["type"] = "context", ["id"] = contextId})

    local url = idolServer
                .. "?action=manageResources"
                .. "&data=" .. base64_encode(to_send_obj:string())

    local request = LuaHttpRequest:new(config, "http")

    request:set_url(url)

    local response = request:send()

    log_info("IDOL Request:", url)
    log_info("IDOL Response:", response:get_body())
end

function handler(ffdocument, session)

    local securityInfo = ffdocument:getAttribute("idol.securityinfo")
    local sessionInfoURL = ffdocument:getAttribute("idol.sessioninfo.url", "")
    local idolServer = session:evaluateAttributeExpressions(session:getProperty("IDOLServer"))
    local sessionBackend = session:evaluateAttributeExpressions(session:getProperty("SessionBackend"))
    local sessionMaxSteps = session:evaluateAttributeExpressions(session:getProperty("SessionMaxSteps"))
    local systemOrderCSV = session:evaluateAttributeExpressions(session:getProperty("SystemPreferenceOrder"))
    local contextualAnswerSystem = session:evaluateAttributeExpressions(session:getProperty("ContextualAnswerSystem"))
    local systemOrder = splitOn(systemOrderCSV, ",")
    local matchReferences = getMatchReferences(ffdocument:getAttribute("idol.matchreferences", ""))
    local parametricFilters = ffdocument:getAttribute("idol.parametricfilters", "")

    log_info("IDOL Server:", idolServer)

    ffdocument:setAttribute("routepath", "idol.ask")

    local sessionInfo = nil
    local lastAnswer = nil
    if sessionInfoURL ~= "" then
        sessionInfo, lastAnswer = getSessionData(sessionBackend, sessionInfoURL, sessionMaxSteps)
    end

    local contextId = nil
    if lastAnswer ~= nil then
        contextId = makeContext(idolServer, lastAnswer, contextualAnswerSystem)
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
                            if getAnswer(idolServer, securityInfo, string.sub(content, 1, 2000),
                                        system, docListField, sessionInfo, contextId, matchReferences, parametricFilters) then
                                log_info(string.format("Answer system %s produced answer.", system))
                                break
                            end
                        end
                    end
                )
                action:deletePart()
            end
    })

    if contextId ~= nil then
        destroyContext(idolServer, contextId)
    end

    if not status then
        error(retval)
    end

end