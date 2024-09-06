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
            if #image_list > 0 then
                response["imageHit"] = get_hits(image_list)
            end

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