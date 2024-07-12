
local config_string =
[===[
[http]
ProxyHost=
ProxyPort=
]===]
local config = LuaConfig:new(config_string)


function sendIDOLAction(url)

    local request = LuaHttpRequest:new(config, "http")

    request:set_url(url)

    local response = request:send()

    log_info("IDOL Request:", url)
    log_info("IDOL Response:", response:get_body())

    local responseXml = parse_xml(response:get_body())
    responseXml:XPathRegisterNs("autn", "http://schemas.autonomy.com/aci/")

    return responseXml
end

function sendQueryAction(idolServer, securityInfo, text, maxResults, matchReferences)

    local queryURL = idolServer
        .. "?action=query"
        .. "&SecurityInfo=" .. url_escape(securityInfo)
        .. "&summary=none"
        .. "&print=fields"
        .. "&printfields=none"
        .. "&MaxResults=" .. tostring(maxResults)
        .. "&StoreState=true"
        .. "&text=" .. url_escape(text)

    if matchReferences ~= nil and matchReferences ~= "" then
        queryURL = queryURL .. "&matchreference=" .. matchReferences
    end

    local responseXml = sendIDOLAction(queryURL)

    local errorString = responseXml:XPathValue("/autnresponse/responsedata/error/errorstring")
    local stateToken = responseXml:XPathValue("/autnresponse/responsedata/autn:state")
    local numHits = tonumber(responseXml:XPathValue("/autnresponse/responsedata/autn:numhits") or "0")

    local hitNodeSet = responseXml:XPathExecute("//responsedata/autn:hit")
    local weights = {}
    for i, hitNode in hitNodeSet:ipairs() do
        local reference = responseXml:XPathValue("autn:reference", hitNode)
        local weight = responseXml:XPathValue("autn:weight", hitNode)
        weights[reference] = weight
    end

    return stateToken, numHits, errorString, weights
end

function sendGetContentAction(idolServer, securityInfo, stateId, startIndex, endIndex)

    return sendIDOLAction(idolServer
        .. "?action=getContent"
        .. "&SecurityInfo=" .. url_escape(securityInfo)
        .. "&summary=quick"
        .. "&print=fields"
        .. "&printfields=none"
        .. "&xmlmeta=true"
        .. "&stateId=" .. url_escape(stateId.."["..tostring(startIndex).."-"..tostring(endIndex).."]"))
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

function handler(ffdocument, session)

    local securityInfo = ffdocument:getAttribute("idol.securityinfo")
    local idolServer = session:evaluateAttributeExpressions(session:getProperty("IDOLServer"))
    local pageSize = tonumber(ffdocument:getAttribute("pagesize")) or 10
    local maxResults = tonumber(ffdocument:getAttribute("maxresults")) or 6
    local matchReferences = getMatchReferences(ffdocument:getAttribute("idol.matchreferences", ""))

    log_info("IDOL Server:", idolServer)

    ffdocument:setAttribute("routepath", "idol.query")

    ffdocument:modify({
        onContent =
            function(action)
                action:readContent(
                    function(inputstream)
                        local content = inputstream:read("a")

                        local stateToken, numHits, errorString, weights = sendQueryAction(idolServer, securityInfo, string.sub(content, 1, 2000), maxResults, matchReferences)

                        --TODO: errorString

                        local docListField = action:getXmlMetadata():addChild("IDOLDocList")
                        docListField:addChild("startindex"):setValue(tostring(0))
                        docListField:addChild("pagesize"):setValue(tostring(pageSize))
                        docListField:addChild("numhits"):setValue(tostring(numHits))

                        log_info("IDOL Hit Count:", numHits)

                        if stateToken ~= nil and numhits ~= 0 then

                            docListField:addChild("statetoken"):setValue(tostring(stateToken))

                            local responseXml = sendGetContentAction(idolServer, securityInfo, stateToken, 0, math.min(numHits, pageSize)-1)
                            local hitNodeSet = responseXml:XPathExecute("//responsedata/autn:hit")

                            for i, hitNode in hitNodeSet:ipairs() do
                                local id = responseXml:XPathValue("autn:id", hitNode)
                                local reference = responseXml:XPathValue("autn:reference", hitNode)
                                local summary = responseXml:XPathValue("autn:summary", hitNode)
                                local weight = weights[reference] or "0.0"
                                local title = responseXml:XPathValue("autn:title", hitNode)
                                local database = responseXml:XPathValue("autn:database", hitNode)

                                local documentField = docListField:addChild("IDOLDoc")
                                documentField:addChild("reference"):setValue(reference)
                                documentField:addChild("url"):setValue(idolServer.."?action=GetContent&ID="..id) -- TODO
                                documentField:addChild("database"):setValue(database)
                                if title ~= nil then
                                    documentField:addChild("title"):setValue(title)
                                end
                                documentField:addChild("summary"):setValue(summary)
                                documentField:addChild("weight"):setValue(weight)

                            end
                        end
                    end
                )
                action:deletePart()
            end
    })


end
