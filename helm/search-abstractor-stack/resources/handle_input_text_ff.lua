function handler(flowfile, session)
        local text = flowfile:getAttribute("http.query.param.text")
        local ffd = flowfile:getAsFlowFileDocument()
        local sessioninfo = flowfile:getAttribute("http.query.param.sessionid","")
        local resourceid = flowfile:getAttribute("http.query.param.resourceid","")
        ffd:overwrite(function(action)
                action:setAttribute("idol.reference", "handleInputText")
                action:setAttribute("idol.securityinfo", flowfile:getAttribute("http.query.param.securityinfo",""))
                if sessioninfo ~= "" then
                    action:setAttribute("idol.sessioninfo.url", sessioninfo)
                end
                action:setAttribute("idol.matchreferences", flowfile:getAttribute("http.query.param.refs", ""))
                action:setAttribute("idol.parametricfilters", flowfile:getAttribute("http.query.param.parametricFilters", ""))
                action:setAttribute("idol.resourceid", resourceid)
                action:setAttribute("processaction", "IDOL")
                action:setAttribute("variant", "Query")
                action:addContent(text)
                end)
    end
    
    