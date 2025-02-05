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

