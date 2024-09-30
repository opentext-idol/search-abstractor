-- BEGIN COPYRIGHT NOTICE
-- Copyright 2024 Open Text.
-- 
-- The only warranties for products and services of Open Text and its affiliates and licensors
-- ("Open Text") are as may be set forth in the express warranty statements accompanying such
-- products and services. Nothing herein should be construed as constituting an additional warranty.
-- Open Text shall not be liable for technical or editorial errors or omissions contained herein.
-- The information contained herein is subject to change without notice.
--
-- END COPYRIGHT NOTICE

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
        local stt_xml_string = "<SPEECH_TO_TEXT>"..transcript.."</SPEECH_TO_TEXT>"
        local stt_xml = parse_xml(stt_xml_string)
        document:insertXml(stt_xml:root(), "SPEECH_TO_TEXT")
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
        local ocr_xml_string = "<OPTICAL_CHARACTER_RECOGNITION>"..ocrtext.."</OPTICAL_CHARACTER_RECOGNITION>"
        local ocr_xml = parse_xml(ocr_xml_string)
        document:insertXml(ocr_xml:root(), "OPTICAL_CHARACTER_RECOGNITION")
    end

    -- Image embedding
    local embeddingresults = document:getValuesByPath("part/idol_media/analyze_media/results/track/record/ImageEmbeddingResult/embedding")
    local embeddingmodel = document:getValuesByPath("part/idol_media/analyze_media/results/track/record/ImageEmbeddingResult/encoder")
    if embeddingresults then
        local xml_string = "<embedding>"..embeddingresults.."</embedding>"
        local xml = parse_xml(xml_string)
        document:insertXml(xml:root(), "VECTOR_"..embeddingmodel)
    end
end