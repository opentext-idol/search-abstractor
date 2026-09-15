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

import dspy

from enum import StrEnum
from typing import Iterable

import vertexai

from vertexai.generative_models import Content, GenerationConfig, GenerationResponse, GenerativeModel, Part
from google.oauth2.service_account import Credentials

class ConversationRole(StrEnum):
    USER = 'user'
    MODEL = 'model'

class VertexLLMClient(dspy.LM):
    def __init__(self, project: str, location: str, model: str, creds_file: str):
        self.project = project
        self.location = location
        self.model = model
        self.creds = Credentials.from_service_account_file(creds_file)
        self.kwargs = {"temperature": 0}

        # Perform the initialization and set up the model
        vertexai.init(
            project=self.project,
            location=self.location,
            credentials=self.creds
        )
        self.vertex_model = GenerativeModel(
            model_name=self.model,
            generation_config=GenerationConfig(
                candidate_count=1,
                max_output_tokens=500,
                temperature=0.0
            ))

    def get_text_from_response(self, response : GenerationResponse|Iterable[GenerationResponse]) -> str:
        if isinstance(response, GenerationResponse):
            response = [response]
        text_response = []
        for chunk in response:
            if chunk.candidates:
                text_response.append(chunk.candidates[0].text)
        if not text_response:
            raise RuntimeError("Cannot get the response text. The response is likely blocked by the safety filters.")
        return ''.join(text_response)

    def generate_chat(self, prompt: str, session_data: list[dict[str, str]]) -> str:
        '''
        Get generated response for prompt + conversation history
        '''
        chat_history = []
        if prompt:
            chat_history.append(Content(
                role=ConversationRole.USER,
                parts=[Part.from_text(prompt)]
            ))
        else:
            for step in session_data:
                match step['role']:
                    case "user":
                        chat_history.append(Content(
                            role=ConversationRole.USER,
                            parts=[Part.from_text(step['content'])]
                        ))
                    case "model":
                        chat_history.append(Content(
                            role=ConversationRole.MODEL,
                            parts=[Part.from_text(step['content'])]
                        ))

        response = self.vertex_model.generate_content(contents=chat_history)
        return [self.get_text_from_response(response)]

    def __call__(self, prompt: str = None, messages: list[str] = None, **kwargs):
        return self.generate_chat(prompt, messages)