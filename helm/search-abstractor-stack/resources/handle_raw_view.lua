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
    
    log_info("ACI Request:", action)
    local response = send_aci_action(idolServerHost, idolServerPort, action, params, timeout)
    log_info("ACI Response:", response)

    local responseXml = nil
    if response ~= nil then
        responseXml = parse_xml(response)
        responseXml:XPathRegisterNs("autn", "http://schemas.autonomy.com/aci/") 
    end
    
    return responseXml
end

function sendContentAction(idolServerHost, idolServerPort, timeout, reference, securityInfo)
    return sendIDOLAction(idolServerHost, idolServerPort, timeout,
           "getcontent", {SecurityInfo = securityInfo, reference = reference, printfields = "CONNECTOR_GROUP"})
end

function handler(ff, session)
    local idolServerHost = session:evaluateAttributeExpressions(session:getProperty("IDOLServerHost"))
    local idolServerPort = session:evaluateAttributeExpressions(session:getProperty("IDOLServerPort"))
    local small_timeout = tonumber(session:getProperty("ACIServerTimeoutSmall"))
    -- NOTE: The input reference should be url_escaped
    local reference = string.match(ff:getAttribute("http.request.uri"), "/document/(.+)/raw")  
    ff:setAttribute("idol.securityinfo", ff:getAttribute("http.query.param.securityinfo",""))

    log_info("IDOL Server Host:", idolServerHost)
    log_info("IDOL Server Port:", idolServerPort)

    responseXml = sendContentAction(idolServerHost, idolServerPort, small_timeout, reference, ff:getAttribute("idol.securityinfo"))
    
    local connector_group = responseXml:XPathValue("/autnresponse/responsedata/autn:hit/autn:content/DOCUMENT/CONNECTOR_GROUP")
    local autn_identifier = responseXml:XPathValue("/autnresponse/responsedata/autn:hit/autn:content/DOCUMENT/AUTN_IDENTIFIER")

    log_info("CONNECTOR GROUP:", connector_group)
    
    -- If no connector group or autn_identifier found then set error to reroute ff
    if not (connector_group and autn_identifier) then
        ff:setAttribute("idol.error", "document-view-raw")
        log_info("Could not retrieve document with reference: ", reference)
        return
    end

    ff:setAttribute("idol.reference", "document-view-raw")
    ff:setAttribute("mime.type", "application/x.idol.aci; boundary=unused")
    ff:setAttribute("idol.aci.synchronous", "true")
    ff:setAttribute("idol.aci.action", "view")
    ff:setAttribute("idol.aci.token", "fakeacitoken" .. ff:getAttribute("http.context.identifier"))
    if connector_group ~= nil then
        ff:setAttribute("idol.aci.param.connectorgroup", connector_group)
    end
    ff:setAttribute("idol.aci.param.identifier", autn_identifier)
    ff:writeFlowFile(function(os)
        end)
end
