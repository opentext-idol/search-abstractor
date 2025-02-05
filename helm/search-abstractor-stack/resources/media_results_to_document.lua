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
    -- Speech-to-text
    local sttresults = { document:getValuesByPath("part/idol_media/analyze_media/results/track/record/SpeechToTextResult/text") }
    local words = {}
    for k,v in pairs(sttresults) do
        words[k] = "<SIL>"==v and " " or v
    end
    local transcript = table.concat(words, " ")

    -- Insert STT results into SPEECH_TO_TEXT field using XML format
    if transcript and #transcript > 0 then
        document:addField("SPEECH_TO_TEXT", transcript)
    end

    -- OCR
    local ocrresults = { document:getValuesByPath("part/idol_media/analyze_media/results/track/record/OCRResult/text") }
    local sentences = {}
    for k,v in pairs(ocrresults) do
        sentences[k] = v
    end
    local ocrtext = table.concat(sentences, "\n")

    -- Insert OCR results into OPTICAL_CHARACTER_RECOGNITION field using XML format
    if ocrtext and #ocrtext > 0 then
        document:addField("OPTICAL_CHARACTER_RECOGNITION", ocrtext)
    end

    -- Image embedding
    local embeddingresults = document:getValuesByPath("part/idol_media/analyze_media/results/track/record/ImageEmbeddingResult/embedding")
    local embeddingmodel = document:getValuesByPath("part/idol_media/analyze_media/results/track/record/ImageEmbeddingResult/encoder")
    if embeddingresults then
        document:addField("VECTOR_"..embeddingmodel, embeddingresults)
    end
end