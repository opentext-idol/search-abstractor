function handler(flowfile, session)
    local text = flowfile:getAttribute("http.query.param.text")
    local ffd = flowfile:getAsFlowFileDocument()
    ffd:overwrite(function(action)
            action:setAttribute("idol.reference", "handleInputText")
            action:setAttribute("idol.securityinfo", flowfile:getAttribute("http.query.param.securityinfo",""))
            action:setAttribute("idol.matchreferences", flowfile:getAttribute("http.query.param.refs", ""))
            action:setAttribute("processaction", "IDOL")
            action:setAttribute("variant", "Query")
            action:addContent(text)
    	end)
end

