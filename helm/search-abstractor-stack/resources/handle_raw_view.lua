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

function sendContentAction(IDOLServer, reference, securityInfo)
    return sendACIAction(IDOLServer
        .. "?action=getcontent"
        .. "&SecurityInfo=" .. url_escape(securityInfo)
        .. "&reference=" .. url_escape(reference)
    	.. "&printfields=CONNECTOR_GROUP") 
end

function handler(ff, session)
    local IDOLServer = session:evaluateAttributeExpressions(session:getProperty("IDOLServer"))
    -- NOTE: The input reference should be url_escaped
    local reference = string.match(ff:getAttribute("http.request.uri"), "/document/(.+)/raw")  
    ff:setAttribute("idol.securityinfo", ff:getAttribute("http.query.param.securityinfo",""))

    responseXml = sendContentAction(IDOLServer, reference, ff:getAttribute("idol.securityinfo"))
    
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
