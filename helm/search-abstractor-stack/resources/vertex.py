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

# END COPYRIGHT NOTICE

import os
import itertools
import warnings

from typing import Tuple

from google import genai
from google.genai import types
from google.genai._common import ExperimentalWarning
from google.genai.types import UserContent, ModelContent
from google.genai.local_tokenizer import LocalTokenizer

##
# Configuration for the vertexai initialization
##
VERTEX_PROJECT = os.getenv('OPENTEXT_VERTEX_PROJECT') or 'otl-csd-architecture'
VERTEX_LOCATION = os.getenv('OPENTEXT_VERTEX_LOCATION') or 'us-east4'
VERTEX_MODEL = os.getenv('OPENTEXT_VERTEX_MODEL') or 'gemini-2.5-flash'

# If not provided, "credentials will be ascertained from the environment"
# https://cloud.google.com/vertex-ai/generative-ai/docs/reference/python/latest/vertexai#vertexai_init
VERTEX_CREDENTIALS = os.getenv('OPENTEXT_VERTEX_CREDENTIALS')
if VERTEX_CREDENTIALS and os.path.exists(VERTEX_CREDENTIALS):
    from google.oauth2.service_account import Credentials
    VERTEX_CREDENTIALS = Credentials.from_service_account_file(
        VERTEX_CREDENTIALS,
        scopes=["https://www.googleapis.com/auth/cloud-platform"],
    )
else:
    VERTEX_CREDENTIALS = None

# Perform the initialization and set up the client
vertex_client = genai.Client(
    vertexai=True,
    project=VERTEX_PROJECT,
    location=VERTEX_LOCATION,
    credentials=VERTEX_CREDENTIALS,
    http_options=types.HttpOptions(api_version="v1", timeout=60000),
)
vertex_generation_config = types.GenerateContentConfig(
    candidate_count=1,
    max_output_tokens={{ .Values.saapi.vertexai.maxOutputTokens | default 8192 | int }} or None,
)
vertex_tokenizer = LocalTokenizer(model_name=VERTEX_MODEL)

def get_text_from_response(response: types.GenerateContentResponse) -> str:
    '''
    Extract text from a generate content response.
    '''
    if not response.text:
        raise RuntimeError("Cannot get the response text. The response is likely blocked by the safety filters.")
    return response.text

def generate_single(prompt: str) -> str:
    '''
    Get generated response for a simple prompt, no chat history etc.
    '''
    response = vertex_client.models.generate_content(
        model=VERTEX_MODEL,
        contents=prompt,
        config=vertex_generation_config,
    )
    return get_text_from_response(response)

def generate_chat(prompt: str, session_data: list[dict[str, str]]) -> str:
    '''
    Get generated response for prompt + conversation history
    '''
    chat_history = []
    for step in session_data:
        if 'question' in step:
            chat_history.append(UserContent(step['question']))
        if 'answer' in step:
            chat_history.append(ModelContent(step['answer']))
    chat_history.append(UserContent(prompt))

    response = vertex_client.models.generate_content(
        model=VERTEX_MODEL,
        contents=chat_history,
        config=vertex_generation_config,
    )
    return get_text_from_response(response)

def generate(prompt: str, generation_utils=None) -> str:
    '''
    Calls out to VertexAI API with {VERTEX_MODEL} to obtain a generated response from
    the provided prompt
    '''
    if generation_utils is not None:
        return generate_chat(prompt, generation_utils.session_data)
    else:
        return generate_single(prompt)


def get_token_count(text: str, token_limit: int) -> Tuple[str, int]:
    '''
    Uses LocalTokenizer from google.genai to tokenize the provided text,
    truncate it if its token count exceeds token_limit, and return the
    number of tokens in the original text.
    '''
    # N.B. Not sure how to quantify any 'special' tokens VertexAI uses
    with warnings.catch_warnings():
        warnings.filterwarnings('ignore', category=ExperimentalWarning)
        original_token_count = vertex_tokenizer.count_tokens(text).total_tokens
        truncated_text = text
        if original_token_count > token_limit:
            # This will just tokenize the raw text (i.e. without special tokens)
            tokenization_results = vertex_tokenizer.compute_tokens(text)
            iter_tokens = itertools.chain.from_iterable(info.tokens for info in tokenization_results.tokens_info)
            truncated_text = b''.join(itertools.islice(iter_tokens, token_limit)).decode('utf-8', errors='backslashreplace')

    return truncated_text, original_token_count