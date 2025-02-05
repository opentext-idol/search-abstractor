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

function sendGetContentAction(idolServerHost, idolServerPort, timeout, securityInfo, stateId, startIndex, endIndex)

    return sendIDOLAction(idolServerHost, idolServerPort, timeout,
           "getContent", {SecurityInfo = securityInfo, summary = "quick", print = "none",
            stateId = stateId.."["..tostring(startIndex).."-"..tostring(endIndex).."]"})
end

function handler(ffdocument, session)

    local securityInfo = ffdocument:getAttribute("idol.securityinfo")
    local idolServerHost = session:evaluateAttributeExpressions(session:getProperty("IDOLServerHost"))
    local idolServerPort = session:evaluateAttributeExpressions(session:getProperty("IDOLServerPort"))
    local small_timeout = tonumber(session:getProperty("ACIServerTimeoutSmall"))
    local summaryType = "quick"
    local stateToken = ffdocument:getAttribute("statetoken")
    local startIndex = tonumber(ffdocument:getAttribute("startindex"))
    local pageSize = tonumber(ffdocument:getAttribute("pagesize"))
    local numHits = tonumber(ffdocument:getAttribute("numhits"))
    
    
    log_info("IDOL Server Host:", idolServerHost)
    log_info("IDOL Server Port:", idolServerPort)
    
    ffdocument:modify({
        postAction =
            function(action)      
                local docListField = action:getXmlMetadata():addChild("IDOLDocList")
                docListField:addChild("startindex"):setValue(tostring(startIndex))
                docListField:addChild("pagesize"):setValue(tostring(pageSize))
                docListField:addChild("statetoken"):setValue(tostring(stateToken))
                docListField:addChild("numhits"):setValue(tostring(numHits))

                if stateToken ~= nil and numhits ~= 0 then

                    local responseXml = sendGetContentAction(idolServerHost, idolServerPort, small_timeout, securityInfo, stateToken, startIndex, startIndex+pageSize-1)
                    if responseXml == nil then
                        return
                    end
                    local hitNodeSet = responseXml:XPathExecute("//responsedata/autn:hit");

                    for i, hitNode in hitNodeSet:ipairs() do 
                        local id = responseXml:XPathValue("autn:id", hitNode);
                        local reference = responseXml:XPathValue("autn:reference", hitNode);
                        local summary = responseXml:XPathValue("autn:summary", hitNode);

                        local documentField = docListField:addChild("IDOLDoc")
                        documentField:addChild("reference"):setValue(reference)
                        documentField:addChild("url"):setValue("http://"..idolServerHost..":"..idolServerPort.."/?action=GetContent&ID="..id) -- TODO
                        documentField:addChild("summary"):setValue(summary)
                    end
                end
            end
    })
   
    
end