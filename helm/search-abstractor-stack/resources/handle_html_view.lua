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

    return response
end
    
function sendViewAction(idolServerHost, idolServerPort, timeout, reference, securityInfo, urlPrefix)
    log_info("VIEW REFERENCE:", reference)
    return sendIDOLAction(idolServerHost, idolServerPort, timeout,
           "view", {SecurityInfo = securityInfo, reference = url_unescape(reference), noaci = "true", outputtype = "html",
           urlprefix = urlPrefix .. "document/" .. reference .. "/html/subfile?linkspec="})
end

function sendGetLinkAction(idolServerHost, idolServerPort, timeout, reference)
    log_info("GETLINK REFERENCE:", reference)
    local response = sendIDOLAction(idolServerHost, idolServerPort, timeout,
               "getlink", {noaci = "false", linkspec = reference})
    
    local responseXml = nil
    if response ~= nil then
        responseXml = parse_xml(response)
        responseXml:XPathRegisterNs("autn", "http://schemas.autonomy.com/aci/") 
    end
    return responseXml
end

function handler(ffd, session)
    local idolServerHost = session:evaluateAttributeExpressions(session:getProperty("IDOLServerHost"))
    local idolServerPort = session:evaluateAttributeExpressions(session:getProperty("IDOLServerPort"))
    local small_timeout = tonumber(session:getProperty("ACIServerTimeoutSmall"))
    local urlPrefix = session:evaluateAttributeExpressions(session:getProperty("ViewURLPrefix"))
    local request = ffd:getAttribute("http.request.uri")
    local response = ""
    local linkspec = ffd:getAttribute("http.query.param.linkspec","")
    ffd:setAttribute("idol.reference", "document-view-html")
    ffd:setAttribute("idol.securityinfo", ffd:getAttribute("http.query.param.securityinfo",""))
        
    if linkspec == nil or linkspec == "" then
        -- document html view request
        -- NOTE: The input reference should be url_escaped
    	response = sendViewAction(idolServerHost, idolServerPort, small_timeout, string.match(request, "/document/(.+)/html"), ffd:getAttribute("idol.securityinfo"), urlPrefix)
    else
        -- subdocument handling request
        -- NOTE: The link should be url_escaped
    	responseXml = sendGetLinkAction(idolServerHost, idolServerPort, small_timeout, linkspec)
        log_info("http.query.string", ffd:getAttribute("http.query.string"))
        if responseXml~=nil then
            local response_b64 = responseXml:XPathValue("//responsedata/content")
            response = base64_decode(response_b64)
        end
    end
            
    log_info("IDOL Server Host:", idolServerHost)
    log_info("IDOL Server Port:", idolServerPort)

    ffd:modify(
        function(action)
            action:addFile(function(outputstream)
                outputstream:write(response)
            end)
        end)
    return
end
