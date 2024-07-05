local config_string =
[===[
[http]
ProxyHost=
ProxyPort=
]===]
local config = LuaConfig:new(config_string)
local RAG_TYPE_NAME = "rag"


local function sendIDOLAction(url)

    local request = LuaHttpRequest:new(config, "http")

    request:set_url(url)

    local response = request:send()

    log_info("IDOL Request:", url)
    log_info("IDOL Response:", response:get_body())

    local responseXml = parse_xml(response:get_body())
    responseXml:XPathRegisterNs("autn", "http://schemas.autonomy.com/aci/")

    return responseXml
end

local function sendAskAction(idolServer, securityInfo, text, system, matchReferences)

    local askURL = idolServer
        .. "?action=Ask"
        .. "&CustomizationData=" .. url_escape("[{\"system_name\":\"RAGPassageExtractor\",\"security_info\":\""..securityInfo.."\"},{\"system_name\":\"LLMPassageExtractor\",\"security_info\":\""..securityInfo.."\"}]")
        .. "&SystemNames=" .. url_escape(system)
        .. "&text=" .. url_escape(text)

    if matchReferences ~= nil and matchReferences ~= "" then
        askURL = askURL .. "&matchreference=" .. matchReferences
    end

    return sendIDOLAction(askURL)
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

local function getAnswer(idolServer, securityInfo, input, system, docListField, matchReferences)
    local responseXml = sendAskAction(idolServer, securityInfo, input, system, matchReferences)
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

function handler(ffdocument, session)

    local securityInfo = ffdocument:getAttribute("idol.securityinfo")
    local idolServer = session:evaluateAttributeExpressions(session:getProperty("IDOLServer"))
    local systemOrderCSV = session:evaluateAttributeExpressions(session:getProperty("SystemPreferenceOrder"))
    local systemOrder = splitOn(systemOrderCSV, ",")
    local matchReferences = getMatchReferences(ffdocument:getAttribute("idol.matchreferences", ""))

    log_info("IDOL Server:", idolServer)

    ffdocument:setAttribute("routepath", "idol.ask")

    ffdocument:modify({
        onContent =
            function(action)
                action:readContent(
                    function(inputstream)
                        local content = inputstream:read("a")
                        local docListField = action:getXmlMetadata():addChild("IDOLDocList")

                        for _, system in ipairs(systemOrder) do
                            log_info(string.format("Trying answer system %s to find answer...", system))
                            if getAnswer(idolServer, securityInfo, string.sub(content, 1, 2000), system, docListField, matchReferences) then
                                log_info(string.format("Answer system %s produced answer.", system))
                                break
                            end
                        end
                    end
                )
                action:deletePart()
            end
    })

end