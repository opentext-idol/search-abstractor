-- BEGIN COPYRIGHT NOTICE
-- Copyright 2024 Open Text.
-- 
-- The only warranties for products and services of Open Text and its affiliates and licensors
-- ("Open Text") are as may be set forth in the express warranty statements accompanying such
-- products and services. Nothing herein should be construed as constituting an additional warranty.
-- Open Text shall not be liable for technical or editorial errors or omissions contained herein.
-- The information contained herein is subject to change without notice.
--
-- END COPYRIGHT NOTICE

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

function sendQueryAction(idolServer, securityInfo, text, maxResults, matchReferences, parametricFilters, vectorfield)

    local input_text = text
    if vectorfield then
        input_text = "VECTOR{" .. text .. "}:" .. vectorfield
    end

    local queryURL = idolServer
        .. "?action=query"
        .. "&SecurityInfo=" .. url_escape(securityInfo)
        .. "&summary=none"
        .. "&print=fields"
        .. "&printfields=none"
        .. "&MaxResults=" .. tostring(maxResults)
        .. "&StoreState=true"
        .. "&text=" .. url_escape(input_text)

    if matchReferences ~= nil and matchReferences ~= "" then
        queryURL = queryURL .. "&matchreference=" .. matchReferences
    end

    local docQueryURL = queryURL .. "&fieldtext=" .. url_escape("NOT MATCH{4}:DOCUMENT_KEYVIEW_CLASS_STRING")
    local imageQueryURL = queryURL .. "&fieldtext=" .. url_escape("MATCH{4}:DOCUMENT_KEYVIEW_CLASS_STRING")
    if parametricFilters ~= nil and parametricFilters ~= "" then
        docQueryURL = docQueryURL .. " AND (" .. parametricFilters .. ")"
        imageQueryURL = imageQueryURL .. " AND (" .. parametricFilters .. ")"
    end
    

    local label = "IDOLDoc"
    local toSend = docQueryURL
    if vectorfield then
        label = "IDOLImage"
        toSend = imageQueryURL
    end

    local responseXml = sendIDOLAction(toSend)

    local errorString = {["IDOLDoc"] = nil, ["IDOLImage"] = nil}
    errorString[label] = responseXml:XPathValue("/autnresponse/responsedata/error/errorstring")
    local stateToken = {["IDOLDoc"] = nil, ["IDOLImage"] = nil}
    local numHits = {["IDOLDoc"] = 0, ["IDOLImage"] = 0}
    stateToken[label] = responseXml:XPathValue("/autnresponse/responsedata/autn:state")
    numHits[label] = tonumber(responseXml:XPathValue("/autnresponse/responsedata/autn:numhits") or "0")

    local hitNodeSet = responseXml:XPathExecute("//responsedata/autn:hit")
    local weights = {}
    for _, hitNode in hitNodeSet:ipairs() do
        local reference = responseXml:XPathValue("autn:reference", hitNode)
        local weight = responseXml:XPathValue("autn:weight", hitNode)
        weights[reference] = weight
    end

    if vectorfield == nil then
        imageQueryURL = imageQueryURL .. "&querytype=vector,conceptual&vectorconfig=VModel_clip"
        local imageResponseXML = sendIDOLAction(imageQueryURL)

        errorString["IDOLImage"] = imageResponseXML:XPathValue("/autnresponse/responsedata/error/errorstring")
        stateToken["IDOLImage"] = imageResponseXML:XPathValue("/autnresponse/responsedata/autn:state")
        numHits["IDOLImage"] = tonumber(imageResponseXML:XPathValue("/autnresponse/responsedata/autn:numhits") or "0")

        local imageHitNodeSet = imageResponseXML:XPathExecute("//responsedata/autn:hit")
        for _, hitNode in imageHitNodeSet:ipairs() do
            local reference = imageResponseXML:XPathValue("autn:reference", hitNode)
            local weight = imageResponseXML:XPathValue("autn:weight", hitNode)
            weights[reference] = weight
        end
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

local function writeDocListFields(numHits, stateToken, docListField, idolServer, securityInfo, pageSize, weights, label)
    docListField:addChild("startindex"):setValue(tostring(0))
    docListField:addChild("pagesize"):setValue(tostring(pageSize))
    docListField:addChild("numhits"):setValue(tostring(numHits[label]))
    log_info("IDOL Hit Count:", numHits[label])

    if stateToken[label] ~= nil and numHits[label] ~= 0 then

        docListField:addChild("statetoken"):setValue(tostring(stateToken[label]))

        local responseXml = sendGetContentAction(idolServer, securityInfo, stateToken[label], 0, math.min(numHits[label], pageSize)-1)
        local hitNodeSet = responseXml:XPathExecute("//responsedata/autn:hit")

        for i, hitNode in hitNodeSet:ipairs() do
            local id = responseXml:XPathValue("autn:id", hitNode)
            local reference = responseXml:XPathValue("autn:reference", hitNode)
            local summary = responseXml:XPathValue("autn:summary", hitNode)
            local weight = weights[reference] or "0.0"
            local title = responseXml:XPathValue("autn:title", hitNode)
            local database = responseXml:XPathValue("autn:database", hitNode)

            local documentField = docListField:addChild(label)
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

function handler(ffdocument, session)

    local securityInfo = ffdocument:getAttribute("idol.securityinfo")
    local idolServer = session:evaluateAttributeExpressions(session:getProperty("IDOLServer"))
    local pageSize = tonumber(ffdocument:getAttribute("pagesize")) or 10
    local maxResults = tonumber(ffdocument:getAttribute("maxresults")) or 6
    local matchReferences = getMatchReferences(ffdocument:getAttribute("idol.matchreferences", ""))
    local parametricFilters = ffdocument:getAttribute("idol.parametricfilters", "")
    local resourceid = ffdocument:getAttribute("idol.resourceid")
    local imageVectorField = session:evaluateAttributeExpressions(session:getProperty("ImageVectorField"))

    log_info("IDOL Server:", idolServer)

    ffdocument:setAttribute("routepath", "idol.query")

    ffdocument:modify({
        onContent =
            function(action)
                action:readContent(
                    function(inputstream)
                        local content = inputstream:read("a")
                        
                        local stateToken, numHits, errorString, weights
                        if resourceid == nil or resourceid == "" then
                            stateToken, numHits, errorString, weights = sendQueryAction(idolServer, securityInfo, string.sub(content, 1, 2000),
                                                                                            maxResults, matchReferences, parametricFilters)
                        else
                            stateToken, numHits, errorString, weights = sendQueryAction(idolServer, securityInfo, content, maxResults,
                                                                                            matchReferences, parametricFilters, imageVectorField)
                        end

                        --TODO: errorString

                        local docListField = action:getXmlMetadata():addChild("IDOLDocList")
                        writeDocListFields(numHits, stateToken, docListField, idolServer, securityInfo, pageSize, weights, "IDOLDoc")
                        
                        local imageListField = action:getXmlMetadata():addChild("IDOLImageList")
                        writeDocListFields(numHits, stateToken, imageListField, idolServer, securityInfo, pageSize, weights, "IDOLImage")
                    end
                )
                action:deletePart()
            end
    })


end