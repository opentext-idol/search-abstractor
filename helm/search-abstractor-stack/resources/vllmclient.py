#
# Copyright 2024-2026 Open Text.
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

import requests

try:
    import dspy
except:
    from idolnifi import installPackage,PersistentPackageDirectory
    installPackage('dspy==3.0.4', packageDirectory=PersistentPackageDirectory)
    
    import dspy

class VLLMClient(dspy.LM):
    propertyPrefix = "vllm."

    @classmethod
    def create_from_props(cls, properties: dict[str,str]):
        return cls(model=properties["model"],
                   api_base=properties["apibase"],
                   api_key=properties.get("apikey"))

    def __init__(self, model: str, api_base: str, api_key: str = None):
        self.model = model
        self.api_base = api_base.rstrip('/')
        self.api_key = api_key
        self.headers = {"Content-Type": "application/json"}
        self.kwargs = {"temperature": 0}
        if api_key:
            self.headers["Authorization"] = f"Bearer {api_key}"

    def _call_api(self, prompt, messages):
        #Currently we just use this for chat, so there is no prompt
        url = self.api_base
        payload = {
            "model": self.model,
            "max_tokens": 500,
            "n": 1,
            "temperature": self.kwargs["temperature"]
        }
        if prompt:
            payload["prompt"] = prompt
        elif messages:
            payload["messages"] = messages
        else:
            raise ValueError("Must provide either prompt or messages")
        response = requests.post(url, json=payload, headers=self.headers)
        response.raise_for_status()
        data = response.json()
        return [data["choices"][0]["message"]["content"]]

    def __call__(self, prompt: str = None, messages: list[str] = None, **kwargs):
        return self._call_api(prompt, messages)