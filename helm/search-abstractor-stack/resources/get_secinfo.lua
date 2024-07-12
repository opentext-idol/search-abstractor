local config_string =
[===[
[http]
ProxyHost=
ProxyPort=
]===]
local config = LuaConfig:new(config_string)


function sendACIAction(url)

    local request = LuaHttpRequest:new(config, "http")

    request:set_url(url)

    local response = request:send()

    log_info("ACI Request:", url)
    log_info("ACI Response:", response:get_body())

    local responseXml = parse_xml(response:get_body())
    responseXml:XPathRegisterNs("autn", "http://schemas.autonomy.com/aci/")
    
    return responseXml   
end

function sendCommunityAction(communityServer, audience)

    local responseXml = sendACIAction(communityServer
        .. "?action=UserRead"
        .. "&Username=" .. url_escape(audience)
        .. "&SecurityInfo=true")

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
    local communityServer = session:evaluateAttributeExpressions(session:getProperty("CommunityServer"))
    
    log_info("Community Server:", idolServer)
    log_info("Audience:", audience)
    
    if string.find(audience, ",") then
        log_info("Failed to get SecInfo for " .. audience .. ": Multiple users in audience")
    else
        local result, errorString = sendCommunityAction(communityServer, base64_decode(audience))

        if result then	
            ffdocument:setAttribute("idol.securityinfo", result)
        else
            log_warn("Failed to get SecInfo for " .. audience .. ": ".. errorString)
        end
    end

   
    
end
