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

from enum import StrEnum
from typing import Iterable

from idolnifi import *

try:
    import dspy
    from google import genai
    from google.genai import types
    from google.genai.types import UserContent, ModelContent
except:
    from idolnifi import installPackage,PersistentPackageDirectory
    installPackage('dspy==3.0.4', packageDirectory=PersistentPackageDirectory)
    installPackage('google-genai[local-tokenizer]==1.73.1', packageDirectory=PersistentPackageDirectory)

    import dspy
    from google import genai
    from google.genai import types
    from google.genai.types import UserContent, ModelContent

from google.oauth2.service_account import Credentials

class VertexClient(dspy.LM):
    propertyPrefix = "vertex."

    @classmethod
    def create_from_props(cls, properties: dict[str,str]):
        return cls(project=properties["project"],
                   location=properties["location"],
                   model=properties["model"],
                   creds_file=properties["creds_file"])

    def __init__(self, project: str, location: str, model: str, creds_file: str):
        self.project = project
        self.location = location
        self.model = model
        self.creds = Credentials.from_service_account_file(
            creds_file,
            scopes=["https://www.googleapis.com/auth/cloud-platform"],
        )
        self.kwargs = {"temperature": 0}

        self.client = genai.Client(
            vertexai=True,
            project=self.project,
            location=self.location,
            credentials=self.creds,
            http_options=types.HttpOptions(api_version="v1"),
        )
        self.generation_config = types.GenerateContentConfig(
            candidate_count=1,
            max_output_tokens={{ .Values.saapi.vertexai.maxOutputTokens | default 8192 | int }} or None,
            temperature=0.0,
        )

    def generate_chat(self, prompt: str, session_data: list[dict[str, str]]) -> str:
        '''
        Get generated response for prompt + conversation history
        '''
        if prompt:
            contents = UserContent(prompt)
        else:
            contents = []
            for step in session_data:
                match step['role']:
                    case "user":
                        contents.append(UserContent(step['content']))
                    case "model":
                        contents.append(ModelContent(step['content']))

        response = self.client.models.generate_content(
            model=self.model,
            contents=contents,
            config=self.generation_config,
        )
        text = response.text
        if text is None:
            raise RuntimeError("Cannot get the response text. The response is likely blocked by the safety filters.")
        return [text]

    def __call__(self, prompt: str = None, messages: list[str] = None, **kwargs):
        return self.generate_chat(prompt, messages)