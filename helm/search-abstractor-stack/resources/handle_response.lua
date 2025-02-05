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
local HIT_FIELD_MAPPINGS = {["reference"] = "ref", ["database"] = "source", ["title"] = "title",
                            ["weight"] = "relevance"}

local function get_hits(doc_list)
    local hits = LuaJsonArray:new()
    for _, child in ipairs(doc_list) do
        local hit = {}
        local child_list = { child:getChildren() }
        for _, field in ipairs(child_list) do
            local mapped_field = HIT_FIELD_MAPPINGS[field:getName()]
            if mapped_field ~= nil then
                if mapped_field == "relevance" then
                    hit[mapped_field] = tonumber(field:getValue())
                else
                    hit[mapped_field] = field:getValue()
                end
            end
        end
        hits:append(LuaJsonObject:new(hit))
    end
    return hits
end

local function query_handler(ffdocument, session)
    ffdocument:modify({
        postAction = function(action)
            local meta = action:getXmlMetadata()
            local response = {["responseType"] = "searchresult"}
            
            local doc_list = { meta:getElementsByXPath("//xmlmetadata/IDOLDocList/IDOLDoc") }
            response["hit"] = get_hits(doc_list)

            local image_list = { meta:getElementsByXPath("//xmlmetadata/IDOLImageList/IDOLImage") }
            response["imageHit"] = get_hits(image_list)

            local json_response = LuaJsonObject:new({["response"] = LuaJsonObject:new(response)})
            action:addContent(json_response:string())
            action:clearXmlMetadata()
        end})
end

local ANSWER_FIELD_MAPPINGS = {["source"] = "ref", ["paragraph"] = "text", ["title"] = "title", ["database"] = "source"}

local function ask_handler(ffdocument, session)
    ffdocument:modify({
        postAction = function(action)
            local meta = action:getXmlMetadata()
            local response = {["responseType"] = "answer", ["text"] = ""}
            local sources = LuaJsonArray:new()
            local doc_list = { meta:getElementsByXPath("//xmlmetadata/IDOLDocList/IDOLDoc") }
            for _, child in ipairs(doc_list) do
                local child_list = { child:getChildren() }
                local response_sources = {}
                for __, field in ipairs(child_list) do
                    if field:getName() == "text" then
                        response["text"] = field:getValue()
                    else
                        local base_field
                        for k in pairs(ANSWER_FIELD_MAPPINGS) do
                            base_field = string.match(field:getName(), "^" .. k)
                            if base_field then
                                break
                            end
                        end
                        local mapped_field = ANSWER_FIELD_MAPPINGS[base_field]
                        if mapped_field ~= nil then
                            if mapped_field == "ref" then
                                -- create new source object
                                table.insert(response_sources, {["ref"] = field:getValue()})
                            elseif mapped_field == "relevance" then
                                response_sources[#response_sources]["relevance"] = tonumber(field:getValue())
                            else
                                response_sources[#response_sources][mapped_field] = field:getValue()
                            end
                        end
                    end
                end
                -- create source object for each entry in response_sources
                for _,source in ipairs(response_sources) do
                    if source["source"] == nil then
                        source["source"] = ""
                    end
                    if source["title"] == nil then
                        source["title"] = ""
                    end
                    sources:append(LuaJsonObject:new(source))
                end
            end

            response["sources"] = sources
            local json_response = LuaJsonObject:new({["response"] = LuaJsonObject:new(response)})
            action:addContent(json_response:string())
            action:clearXmlMetadata()
        end})
end

local ROUTE_MAP = {["idol.ask"] = ask_handler, ["idol.query"] = query_handler}

function handler(ffdocument, session)
    local route = ffdocument:getAttribute("routepath")

    local route_handler = ROUTE_MAP[route]
    if route_handler ~= nil then
        route_handler(ffdocument, session)
    end
end