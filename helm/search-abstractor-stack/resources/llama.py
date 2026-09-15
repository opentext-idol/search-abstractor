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

import os

from typing import Tuple

import requests

from transformers import AutoTokenizer

NO_PROXIES = {'http': None, 'https': None}

LLAMA_BASE = os.getenv('OPENTEXT_LLAMA_ENDPOINT_BASE') or 'http://llama-server:8000/v1'
LLAMA_BASE_URL = f"{LLAMA_BASE}/chat/completions"
LLAMA_MODEL = os.getenv('OPENTEXT_LLAMA_MODEL') or 'llama-4-17b-maverick'
LLAMA_API_KEY = os.getenv('OPENTEXT_LLAMA_API_KEY') or 'My API Key'
LLAMA_HF_MODEL = os.getenv('OPENTEXT_LLAMA_HUGGINGFACE_MODEL') or 'meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8'
LLAMA_MODEL_REVISION = os.getenv('OPENTEXT_LLAMA_MODEL_REVISION') or 'main'

HUGGINGFACE_API_TOKEN = os.getenv('OPENTEXT_LLAMA_HUGGINGFACE_API_TOKEN')
if HUGGINGFACE_API_TOKEN is not None:
    from huggingface_hub import login
    # Authenticate with Hugging Face
    login(HUGGINGFACE_API_TOKEN)

def get_choice_from_response(response):
    response_json = response.json()
    if 'choices' not in response_json:
        raise RuntimeError(f"Unable to find 'choices' in Llama response:\n{response.text}")

    choices = response_json['choices']
    if len(choices) == 0:
        raise RuntimeError(f"'choices' is invalid in Llama response:\n{response.text}")

    return choices[0]

def get_headers():
    return {'Authorization': f'Bearer {LLAMA_API_KEY}'}

def generate_chat(url: str, prompt: str, session_data: list[dict[str, str]]) -> str:
    chat_history = []
    for step in session_data:
        if 'question' in step:
            chat_history.append({"role": "user", "content": step["question"]})
        if 'answer' in step:
            chat_history.append({"role": "assistant", "content": step["answer"]})

    chat_history.append({"role": "user", "content": prompt})

    data = {
        "model": LLAMA_MODEL,
        "max_tokens": 500,
        "n": 1,
        "messages": chat_history,
        "temperature": 0
    }

    response = requests.post(url, headers=get_headers(), json=data, timeout=600, proxies=NO_PROXIES)
    response.raise_for_status()

    first_choice = get_choice_from_response(response)
    if 'message' not in first_choice:
        raise RuntimeError(f"'message' not found in first 'choices' element in Llama response:\n{response.text}")

    message = first_choice['message']
    if 'content' not in message:
        raise RuntimeError(f"'content' not found in message element within first 'choices' element in Llama response:\n{response.text}")
    return message['content']

def generate(prompt: str, generation_utils=None) -> str:
    '''
    Calls out to a Llama endpoint to obtain a generated response from
    the provided prompt
    '''
    if generation_utils is not None:
        return generate_chat(LLAMA_BASE_URL, prompt, generation_utils.session_data)
    else:
        return generate_chat(LLAMA_BASE_URL, prompt, [])


def get_token_count(text: str, token_limit: int) -> Tuple[str, int]:
    '''
    Uses the AutoTokenizer from the transformers library to tokenize the provided text,
    truncate it if its token count exceeds token_limit, and return the number of tokens
    (including special tokens) in the original text.
    '''
    try:
        tokenizer = AutoTokenizer.from_pretrained(LLAMA_HF_MODEL, revision=LLAMA_MODEL_REVISION, local_files_only=HUGGINGFACE_API_TOKEN is None)
    except Exception as ex:
        raise

    chat_completion_tokenized = tokenizer.encode(text, add_special_tokens=True)

    original_token_count = len(chat_completion_tokenized)

    truncated_text = text
    if original_token_count > token_limit:
        # This will just tokenize the raw text (i.e. without special tokens).
        tokenized_text_no_specials = tokenizer.encode(text, add_special_tokens=False)
        special_token_count = original_token_count - len(tokenized_text_no_specials)

        # Need to ensure that <raw_text_tokenized_count> + <special_token_count> <= token_limit, but we want at least one.
        truncated_text_token_limit = max(token_limit - special_token_count, 1)
        truncated_text_tokenized = tokenized_text_no_specials[:truncated_text_token_limit]
        truncated_text = tokenizer.decode(truncated_text_tokenized, clean_up_tokenization_spaces=True)

    return truncated_text, original_token_count
