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

function sendCommunityAction(communityServeHost, communityServePort, timeout, audience)

    local responseXml = sendIDOLAction(communityServeHost, communityServePort, timeout,
        "UserRead", {Username = audience, SecurityInfo = "true"})

    local errorString = responseXml:XPathValue("/autnresponse/responsedata/error/errordescription")
    local resultString = responseXml:XPathValue("/autnresponse/responsedata/autn:securityinfo")
        
    return resultString, errorString
end

function handler(ffdocument, session)

    local secinfo = ffdocument:getAttribute("idol.securityinfo")
    if secinfo then
        return
    end
    local audience = ffdocument:getAttribute("audience")
    local communityServeHost = session:evaluateAttributeExpressions(session:getProperty("CommunityServerHost"))
    local communityServePort = session:evaluateAttributeExpressions(session:getProperty("CommunityServerPort"))
    local small_timeout = tonumber(session:getProperty("ACIServerTimeoutSmall"))
    
    log_info("Community Server Host:", communityServeHost)
    log_info("Community Server Port:", communityServePort)
    log_info("Audience:", audience)
    
    if string.find(audience, ",") then
        log_info("Failed to get SecInfo for " .. audience .. ": Multiple users in audience")
    else
        local result, errorString = sendCommunityAction(communityServeHost, communityServePort, small_timeout, base64_decode(audience))

        if result then	
            ffdocument:setAttribute("idol.securityinfo", result)
        else
            log_warn("Failed to get SecInfo for " .. audience .. ": ".. errorString)
        end
    end

   
    
end
