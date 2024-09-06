local config_string =
[===[
[http]
ProxyHost=
ProxyPort=
]===]
local config = LuaConfig:new(config_string)

function sendIDOLAction(url)
    log_info("IDOL Request:", url)
    local request = LuaHttpRequest:new(config, "http")
	request:set_url(url)
    local response = request:send()
    log_info("IDOL Response:", response:get_body())
    
    return response:get_body()   
end
    
function sendViewAction(idolServer, reference, securityInfo, urlPrefix)
    log_info("VIEW REFERENCE:", reference)
    return sendIDOLAction(idolServer
        .. "?action=view"
        .. "&SecurityInfo=" .. url_escape(securityInfo)
        .. "&reference=" .. reference
        .. "&noaci=true"
        .. "&outputtype=html"
        .. "&urlprefix=" .. urlPrefix .. "document/" .. url_escape(reference) .. "/html/subfile?linkspec=")
end

function sendGetLinkAction(idolServer, reference)
    log_info("GETLINK REFERENCE:", reference)
    return sendIDOLAction(idolServer
            .. "?action=getlink"
        	.. "&noaci=true"
            .. "&linkspec=" .. reference)
end

function handler(ffd, session)
    local idolServer = session:evaluateAttributeExpressions(session:getProperty("IDOLServer"))
    local urlPrefix = session:evaluateAttributeExpressions(session:getProperty("ViewURLPrefix"))
    local request = ffd:getAttribute("http.request.uri")
    local response = ""
    local linkspec = ffd:getAttribute("http.query.param.linkspec","")
    ffd:setAttribute("idol.reference", "document-view-html")
    ffd:setAttribute("idol.securityinfo", ffd:getAttribute("http.query.param.securityinfo",""))
        
    if linkspec == nil or linkspec == "" then
        -- document html view request
        -- NOTE: The input reference should be url_escaped
    	response = sendViewAction(idolServer, string.match(request, "/document/(.+)/html"), ffd:getAttribute("idol.securityinfo"), urlPrefix)
    else
        -- subdocument handling request
        -- NOTE: The link should be url_escaped
    	response = sendGetLinkAction(idolServer, linkspec)
        log_info("http.query.string", ffd:getAttribute("http.query.string"))
    end
            
    log_info("IDOL Server:", idolServer)

    ffd:modify(
        function(action)
            action:addFile(function(outputstream)
                outputstream:write(response)
            end)
        end)
    return
end
