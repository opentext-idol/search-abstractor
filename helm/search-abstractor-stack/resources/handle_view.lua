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

local utils = require "utils"

function sendIDOLAction(idolServerHost, idolServerPort, timeout, action, params)

    log_info("IDOL Request:", action)
    local response = send_aci_action(idolServerHost, idolServerPort, action, params, timeout)
    log_info("IDOL Response:", response)

    return response
end

local function sanitizeQueryOperators(text)
    local sanitized = string.gsub(text, "[\")(:]", ";")
    return sanitized
end

local function setUpHighlighting(params, highlighting)
    local parsed_spec = parse_json_array(url_unescape(highlighting))
    if parsed_spec == nil then
        log_error("Failed to parse highlighting options as JSON, will not perform highlighting")
        return
    end

    local links = {}
    local start_tags = {}
    local end_tags = {}

    local multi_highlight = (parsed_spec:size() > 1)
    local default_start_tag = ""
    local default_end_tag = ""
    if multi_highlight then
        -- must specify tags explicitly when doing multi-highlighting
        default_start_tag = "<font style=\"background-color:#87bf5e\">"
        default_end_tag = "</font>"
    end
    local encoder = function(text) if multi_highlight then return url_escape(text) else return text end end

    for _, value in parsed_spec:ipairs() do
        if not value:is_object() then
            log_error("Highlighting option in JSON is not an object, will not perform highlighting")
            return
        end
        local value_obj = value:object()
        local type = utils.safeLookup(value_obj, "type", nil)
        local expression = utils.safeLookup(value_obj, "expression", nil)

        if type == nil or expression == nil then
            log_error("Highlighting option in JSON lacks type and/or expression, will not perform highlighting")
            return
        end

        table.insert(start_tags, encoder(utils.safeLookup(value_obj, "tag", default_start_tag)))
        table.insert(end_tags, encoder(utils.safeLookup(value_obj, "closingTag", default_end_tag)))

        if type == "PARAGRAPH" then
            local lines = utils.splitOn(expression, "\n")
            local phrases = {}
            for _, line in ipairs(lines) do
                if line ~= "" then
                    table.insert(phrases, "\"" .. sanitizeQueryOperators(line) .. "\"")
                end
            end
            table.insert(links, encoder(table.concat(phrases, " OR ")))

        elseif type == "QUERY" then
            table.insert(links, encoder(expression))
        else
            log_error(string.format("Highlighting option in JSON contains unknown type '%s', will not perform highlighting"), type)
            return
        end
    end

    if multi_highlight then
        params["MultiHighlight"] = "true"
    end

    params["Links"] = table.concat(links, ";")
    params["StartTag"] = table.concat(start_tags, ";")
    params["EndTag"] = table.concat(end_tags, ";")
    params["Highlight"] = "Proximity"
    params["Boolean"] = "true"
end

function sendViewAction(idolServerHost, idolServerPort, timeout, reference, securityInfo, urlPrefix, highlighting, outputType, noAci)
    log_info("VIEW REFERENCE:", reference)
    local params = {SecurityInfo = securityInfo,
                    reference = url_unescape(reference),
                    noaci = noAci,
                    outputtype = outputType,
                    urlprefix = urlPrefix .. "document/html/subfile?linkspec="}
    if highlighting ~= nil and outputType ~= "raw" then
        setUpHighlighting(params, highlighting)
    end
    return sendIDOLAction(idolServerHost, idolServerPort, timeout, "view", params)
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
    local responseXml = nil
    local linkspec = ffd:getAttribute("http.query.param.linkspec","")
    local reference = ffd:getAttribute("http.query.param.reference", "")
    local outputType = string.match(request, "^/document/(.*)/?")
    local noAci = outputType == "html" and "true" or "false"
    local content = ""
    ffd:setAttribute("idol.reference", "document-view")
    ffd:setAttribute("idol.securityinfo", ffd:getAttribute("http.query.param.securityinfo",""))

    if linkspec == nil or linkspec == "" then
        -- document view request
        -- NOTE: The input reference should be url_escaped
        response = sendViewAction(idolServerHost, idolServerPort, small_timeout, reference, ffd:getAttribute("idol.securityinfo"), urlPrefix, ffd:getAttribute("http.query.param.highlighting"), outputType, noAci)
       	if outputType == "raw" then
            if response ~= nil then
                responseXml = parse_xml(response)
                responseXml:XPathRegisterNs("autn", "http://schemas.autonomy.com/aci/")
            end
            if responseXml~=nil then
                local response_b64 = responseXml:XPathValue("//responsedata/content")
                if response_b64 ~= nil then
                    content = base64_decode(response_b64)
                end
            end
            local mimeType = responseXml:XPathValue("//responsedata/mime-type")
            if mimeType ~= nil then
                ffd:setAttribute("Content-Type", mimeType)
            end
        else
            content = response
        end
    else
        -- subdocument handling request
        -- NOTE: The link should be url_escaped
        responseXml = sendGetLinkAction(idolServerHost, idolServerPort, small_timeout, linkspec)
        log_info("http.query.string", ffd:getAttribute("http.query.string"))
        if responseXml~=nil then
            local response_b64 = responseXml:XPathValue("//responsedata/content")
            content = base64_decode(response_b64)
        end
    end

    log_info("IDOL Server Host:", idolServerHost)
    log_info("IDOL Server Port:", idolServerPort)

    ffd:modify(
        function(action)
            action:addFile(function(outputstream)
            	outputstream:write(content)
            end)
        end)
end
