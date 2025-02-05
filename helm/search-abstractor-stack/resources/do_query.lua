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
function sendIDOLAction(idolServerHost, idolServerPort, timeout, action, params)
    
    log_info("IDOL Request:", action)
    local response = send_aci_action(idolServerHost, idolServerPort, action, params, timeout)
    log_info("IDOL Response:", response)

    local responseXml = nil
    if response ~= nil then
        responseXml = parse_xml(response)
        responseXml:XPathRegisterNs("autn", "http://schemas.autonomy.com/aci/")
    end

    return responseXml
end

function sendQueryAction(idolServerHost, idolServerPort, timeout, securityInfo, text, maxResults, matchReferences, parametricFilters, vectorfield)

    local input_text = text
    if vectorfield then
        input_text = "VECTOR{" .. text .. "}:" .. vectorfield
    end

    local queryAction = "query"
    local params = {SecurityInfo = securityInfo, summary = "quick", print = "none", MaxResults = tostring(maxResults), StoreState = "true", text = input_text}

    if matchReferences ~= nil and matchReferences ~= "" then
        params.matchreference = matchReferences
    end

    local docFieldText = "NOT MATCH{4}:DOCUMENT_KEYVIEW_CLASS_STRING"
    local imageFieldText = "MATCH{4}:DOCUMENT_KEYVIEW_CLASS_STRING"
    log_info("PARAMETRIC FILTERS:", parametricFilters)
    if parametricFilters ~= nil and parametricFilters ~= "" then
        parametricFilters = string.gsub(parametricFilters, "+", " ")
        docFieldText = docFieldText .. " AND (" .. parametricFilters .. ")"
        imageFieldText = imageFieldText .. " AND (" .. parametricFilters .. ")"
    end
    

    local label = "IDOLDoc"
    local fieldTextToSend = docFieldText
    if vectorfield then
        label = "IDOLImage"
        fieldTextToSend = imageFieldText
    end

    params.fieldtext = fieldTextToSend
    local responseXml = sendIDOLAction(idolServerHost, idolServerPort, timeout, queryAction, params)

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

    local response = {[label] = responseXml}

    if vectorfield == nil then
        params.fieldtext = imageFieldText
        params.querytype = "vector,conceptual"
        params.vectorconfig = "VModel_clip"
        local imageResponseXML = sendIDOLAction(idolServerHost, idolServerPort, timeout, queryAction, params)

        errorString["IDOLImage"] = imageResponseXML:XPathValue("/autnresponse/responsedata/error/errorstring")
        stateToken["IDOLImage"] = imageResponseXML:XPathValue("/autnresponse/responsedata/autn:state")
        numHits["IDOLImage"] = tonumber(imageResponseXML:XPathValue("/autnresponse/responsedata/autn:numhits") or "0")

        local imageHitNodeSet = imageResponseXML:XPathExecute("//responsedata/autn:hit")
        for _, hitNode in imageHitNodeSet:ipairs() do
            local reference = imageResponseXML:XPathValue("autn:reference", hitNode)
            local weight = imageResponseXML:XPathValue("autn:weight", hitNode)
            weights[reference] = weight
        end
        response["IDOLImage"] = imageResponseXML
    end

    return stateToken, numHits, errorString, weights, response
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

local function writeDocListFields(numHits, stateToken, docListField, idolServerHost, idolServerPort, timeout, securityInfo, pageSize, weights, response, label)
    docListField:addChild("startindex"):setValue(tostring(0))
    docListField:addChild("pagesize"):setValue(tostring(pageSize))
    docListField:addChild("numhits"):setValue(tostring(numHits[label]))
    log_info("IDOL Hit Count:", numHits[label])

    if stateToken[label] ~= nil and numHits[label] ~= 0 then

        docListField:addChild("statetoken"):setValue(tostring(stateToken[label]))

        local numHitsToUse = math.min(numHits[label], pageSize)
        local responseXml = response[label]
        local hitNodeSet = responseXml:XPathExecute("//responsedata/autn:hit")

        for i, hitNode in hitNodeSet:ipairs() do
            if i >= numHitsToUse then
                break
            end
            local id = responseXml:XPathValue("autn:id", hitNode)
            local reference = responseXml:XPathValue("autn:reference", hitNode)
            local summary = responseXml:XPathValue("autn:summary", hitNode)
            local weight = weights[reference] or "0.0"
            local title = responseXml:XPathValue("autn:title", hitNode)
            local database = responseXml:XPathValue("autn:database", hitNode)

            local documentField = docListField:addChild(label)
            documentField:addChild("reference"):setValue(reference)
            documentField:addChild("url"):setValue("http://"..idolServerHost..":"..idolServerPort.."/".."?action=GetContent&ID="..id) -- TODO
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
    local idolServerHost = session:evaluateAttributeExpressions(session:getProperty("IDOLServerHost"))
    local idolServerPort = session:evaluateAttributeExpressions(session:getProperty("IDOLServerPort"))
    local large_timeout = tonumber(session:getProperty("ACIServerTimeoutLarge"))
    local small_timeout = tonumber(session:getProperty("ACIServerTimeoutSmall"))
    local pageSize = tonumber(ffdocument:getAttribute("pagesize")) or 10
    local maxResults = tonumber(ffdocument:getAttribute("maxresults")) or 6
    local matchReferences = getMatchReferences(ffdocument:getAttribute("idol.matchreferences", ""))
    local parametricFilters = ffdocument:getAttribute("idol.parametricfilters", "")
    local resourceid = ffdocument:getAttribute("idol.resourceid")
    local imageVectorField = session:evaluateAttributeExpressions(session:getProperty("ImageVectorField"))

    log_info("IDOL Server Host:", idolServerHost)
    log_info("IDOL Server Port:", idolServerPort)

    ffdocument:setAttribute("routepath", "idol.query")

    ffdocument:modify({
        onContent =
            function(action)
                action:readContent(
                    function(inputstream)
                        local content = inputstream:read("a")
                        
                        local stateToken, numHits, errorString, weights
                        if resourceid == nil or resourceid == "" then
                            stateToken, numHits, errorString, weights, response = sendQueryAction(idolServerHost, idolServerPort, large_timeout, securityInfo, string.sub(content, 1, 2000),
                                                                                            maxResults, matchReferences, parametricFilters)
                        else
                            stateToken, numHits, errorString, weights, response = sendQueryAction(idolServerHost, idolServerPort, large_timeout, securityInfo, content, maxResults,
                                                                                            matchReferences, parametricFilters, imageVectorField)
                        end

                        --TODO: errorString

                        local docListField = action:getXmlMetadata():addChild("IDOLDocList")
                        writeDocListFields(numHits, stateToken, docListField, idolServerHost, idolServerPort, small_timeout, securityInfo, pageSize, weights, response, "IDOLDoc")
                        
                        local imageListField = action:getXmlMetadata():addChild("IDOLImageList")
                        writeDocListFields(numHits, stateToken, imageListField, idolServerHost, idolServerPort, small_timeout, securityInfo, pageSize, weights, response, "IDOLImage")
                    end
                )
                action:deletePart()
            end
    })


end 
