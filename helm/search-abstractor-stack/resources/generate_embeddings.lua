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
function handler(document)
    -- Ask our QMS server to generate embeddings for given document content and add them to the document

    -- THE USER SHOULD MODIFY THESE PARAMETERS AS APPROPRIATE
    local HOST = "idol-qms"
    local PORT = "16000"
    local LIMIT = 100100 -- Truncate input longer than this number of bytes

    log_info("IDOL Server Host:", HOST)
    log_info("IDOL Server Port:", PORT)
      
    local MODELS = {
        ["Model_minilm_256"]="VECTOR_MINILM_256"
        --["Model_minilm_128"]="VECTOR_MINILM_128",
        --["Model_e5_256"]="VECTOR_E5_256",
        --["Model_vertex_256"]="VECTOR_VERTEX_256"
    }

    local docref = document:getReference()
    log_info(string.format("Processing document '%s'...",docref))

    -- generate embeddings for each section and add them to the document
    local document_offset = 0
    local final_offset = 0
    local section = document
    while section do
        document_offset = final_offset
        local to_send = section:getContent()
        if 0~=#to_send then
         
            if #to_send > LIMIT then
                local orig_length = #to_send
                to_send = string.sub(to_send, 1, LIMIT)
                to_send = string.match(to_send, ".*%s")
                log_info(string.format("Truncating input from %d to %d for document '%s'", orig_length, #to_send, docref))
            end

            for model,fieldname in pairs(MODELS) do
                local action = "modelencode"
                local params = {model = model, docref=url_unescape(docref), length=#to_send, text=to_send}

                local response = send_aci_action(HOST, PORT, action, params, 300000)

                if response ~= nil then
                    local body = response
                    local count = 0
                    for vector in string.gmatch(body, "<autn:vector[ start=\"[0-9]*\" end=\"[0-9]*\" length=\"[0-9]*\"]?>.-</autn:vector>") do
                        local start_offset = string.match(vector, "start=\"([0-9]*)\"")
                        local end_offset = string.match(vector, "end=\"([0-9]*)\"")
                        if start_offset ~= nil and end_offset ~= nil then
                            local actual_start_offset = tonumber(start_offset) + document_offset
                            local actual_end_offset = tonumber(end_offset) + document_offset
                            local i, j = string.find(vector, ">.-<")
                            vector_with_offsets = "<autn:vector>"..vector:sub(i+1, j-1)..";source=DRECONTENT["..actual_start_offset..":"..actual_end_offset.."]"..vector:sub(j,-1)
                            local xml = parse_xml(vector_with_offsets)
                            document:insertXml(xml:root(), fieldname)
                            final_offset = actual_end_offset
                            count = count + 1
                        else
                            local xml = parse_xml(vector)
                            document:insertXml(xml:root(), fieldname)
                            count = count + 1
                        end
                    end
                    log_info(string.format("Generated %s %d embeddings for document '%s'", model, count, docref))
                else
                    log_error(string.format("Failed to get response from server for document '%s'", docref))
                end
            end
        else
            log_info(string.format("Document '%s' has empty section", docref))
        end
        section = section:getNextSection()
    end
end
