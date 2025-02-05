#
# Copyright 2024-2025 Open Text.
#
# The only warranties for products and services of Open Text and its
# affiliates and licensors ("Open Text") are as may be set forth in the
# express warranty statements accompanying such products and services.
# Nothing herein should be construed as constituting an additional
# warranty. Open Text shall not be liable for technical or editorial
# errors or omissions contained herein. The information contained herein
# is subject to change without notice.
#
# Except as specifically indicated otherwise, this document contains
# confidential information and a valid license is required for possession,
# use or copying. If this work is provided to the U.S. Government,
# consistent with FAR 12.211 and 12.212, Commercial Computer Software,
# Computer Software Documentation, and Technical Data for Commercial Items
# are licensed to the U.S. Government under vendor's standard commercial
# license.
#

from idolnifi import DocumentModifier, executePython, ReadMode, getPropertyDescriptor

import base64
import importlib.util

def processFile(a, openai_llava_model, openai_llava_endpoint_base, openai_llava_api_key):
    content = None
    def processFileCallback(file):
        from openai import OpenAI
        import httpx
        nonlocal content

        mime_type = a.getPartAttribute("mime.type")

        if mime_type not in {'image/jpeg', 'image/jpg', 'image/png', 'image/tiff', 'image/bmp'}:
            raise RuntimeError(f"Unsupported mime type '{mime_type}' for LLaVA processing.")

        image_base64 = base64.b64encode(file.readall()).decode('utf-8')
        client = OpenAI(
            api_key=openai_llava_api_key,
            base_url=openai_llava_endpoint_base,
            http_client=httpx.Client(trust_env=False),
        )
        chat_response = client.chat.completions.create(
            model=openai_llava_model,
            temperature=0,
            max_tokens=500,
            n=1,
            messages=[{
                "role": "user",
                "content": [
                    {"type": "text", "text": "What's in this image?"},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:{mime_type};base64,{image_base64}"
                        },
                    },
                ],
            }],
        )
        content = chat_response.choices[0].message.content
    a.readFile(processFileCallback, ReadMode.READ_AND_KEEP)
    xml_metadata = a.getXmlMetadata()
    xml_metadata.addChild("LLAVA_DESCRIPTION").setValue(content)
    a.setXmlMetadataString(xml_metadata.toString())

def handler(doc, context):
    properties = context.getProperties()
    openai_llava_model = properties.get(getPropertyDescriptor("OpenaiLlavaModel"), "llava-hf/llava-v1.6-mistral-7b-hf")
    openai_llava_endpoint_base = properties.get(getPropertyDescriptor("OpenaiLlavaEndpointBase"), "http://openai-llava-server:8000/v1/")
    openai_llava_api_key = properties.get(getPropertyDescriptor("OpenaiLlavaApiKey"), "My API Key")

    if not importlib.util.find_spec('httpx'):
        print("pip install: ", executePython(['-m', 'pip', 'install', '-U', 'httpx']))
    if not importlib.util.find_spec('openai'):
        print("pip install: ", executePython(['-m', 'pip', 'install', '-U', 'openai']))
    doc.modify(DocumentModifier()
        .defaultFileAction(lambda a: processFile(a, openai_llava_model, openai_llava_endpoint_base, openai_llava_api_key)))
