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

# END COPYRIGHT NOTICE

import os
import itertools

from enum import StrEnum
from typing import Iterable, Tuple

import vertexai

from vertexai.generative_models import Content, GenerationConfig, GenerationResponse, GenerativeModel, Part
from vertexai.preview.tokenization import get_tokenizer_for_model

##
# Configuration for the vertexai initialization
##
VERTEX_PROJECT = os.getenv('OPENTEXT_VERTEX_PROJECT') or 'otl-csd-architecture'
VERTEX_LOCATION = os.getenv('OPENTEXT_VERTEX_LOCATION') or 'us-east4'
VERTEX_MODEL = os.getenv('OPENTEXT_VERTEX_MODEL') or 'gemini-1.5-flash-001'

# If not provided, "credentials will be ascertained from the environment"
# https://cloud.google.com/vertex-ai/generative-ai/docs/reference/python/latest/vertexai#vertexai_init
VERTEX_CREDENTIALS = os.getenv('OPENTEXT_VERTEX_CREDENTIALS')
if VERTEX_CREDENTIALS and os.path.exists(VERTEX_CREDENTIALS):
    from google.oauth2.service_account import Credentials
    VERTEX_CREDENTIALS = Credentials.from_service_account_file(VERTEX_CREDENTIALS)
else:
    VERTEX_CREDENTIALS = None

# Perform the initialization and set up the model
vertexai.init(
    project=VERTEX_PROJECT,
    location=VERTEX_LOCATION,
    credentials=VERTEX_CREDENTIALS
)
vertex_model = GenerativeModel(
    model_name=VERTEX_MODEL,
    generation_config=GenerationConfig(
        candidate_count=1,
        max_output_tokens={{ .Values.saapi.vertexai.maxOutputTokens | default 500 | int }},
    ))
vertex_tokenizer = get_tokenizer_for_model(VERTEX_MODEL)

def get_text_from_response(response : GenerationResponse|Iterable[GenerationResponse]) -> str:
    '''
    Deal with (i) streamed responses; (ii) potential multiple candidates
    '''
    if isinstance(response, GenerationResponse):
        response = [response]
    text_response = []
    for chunk in response:
        if chunk.candidates:
            text_response.append(chunk.candidates[0].text)
    if not text_response:
        raise RuntimeError("Cannot get the response text. The response is likely blocked by the safety filters.")
    return ''.join(text_response)

def generate_single(model: GenerativeModel, prompt: str) -> str:
    '''
    Get generated response for a simple prompt, no chat history etc.
    '''
    response = model.generate_content(prompt)
    return get_text_from_response(response)

class ConversationRole(StrEnum):
    USER = 'user'
    MODEL = 'model'

def generate_chat(model: GenerativeModel, prompt: str, session_data: list[dict[str, str]]) -> str:
    '''
    Get generated response for prompt + conversation history
    '''
    chat_history = []
    for step in session_data:
        if 'question' in step:
            chat_history.append(Content(
                role=ConversationRole.USER,
                parts=[Part.from_text(step['question'])]
            ))
        if 'answer' in step:
            chat_history.append(Content(
                role=ConversationRole.MODEL,
                parts=[Part.from_text(step['answer'])]
            ))
    chat_history.append(Content(
        role=ConversationRole.USER,
        parts=[Part.from_text(prompt)]
    ))

    response = model.generate_content(contents=chat_history)
    return get_text_from_response(response)

def generate(prompt: str, generation_utils=None) -> str:
    '''
    Calls out to VertexAI API with {VERTEX_MODEL} to obtain a generated response from
    the provided prompt
    '''
    if generation_utils is not None:
        return generate_chat(vertex_model, prompt, generation_utils.session_data)
    else:
        return generate_single(vertex_model, prompt)


def get_token_count(text: str, token_limit: int) -> Tuple[str, int]:
    '''
    Uses model tokenizer from the vertexai.preview.tokenization library to tokenize the
    provided text, truncate it if its token count exceeds token_limit, and return the
    number of tokens in the original text.
    '''
    # N.B. Not sure how to quantify any 'special' tokens VertexAI uses
    original_token_count = vertex_tokenizer.count_tokens(text).total_tokens
    truncated_text = text
    if original_token_count > token_limit:
        # This will just tokenize the raw text (i.e. without special tokens)
        tokenization_results = vertex_tokenizer.compute_tokens(text)
        iter_tokens = itertools.chain.from_iterable(info.tokens for info in tokenization_results.tokens_info)
        truncated_text = b''.join(itertools.islice(iter_tokens, token_limit)).decode('utf-8', errors='backslashreplace')

    return truncated_text, original_token_count