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

import argparse
import dspy
import inspect
import json

from vllm_client import VLLMClient
from vertex_client import VertexLLMClient

#You can implement your own LLM client if required; it should subclass dspy.LM and implement __call__.
#See the above clients for examples.

class ExtractInfo(dspy.Signature):
    """Identify metadata filters (these will be used by a downstream process to query a data index) and subject keywords in the input text. Keywords must not appear in the identified filters. There are no tools available."""

    text: str = dspy.InputField()
    filters: dict[str, str] = dspy.OutputField(desc="a dictionary of filters extracted")
    subject: str = dspy.OutputField(desc="the subject keywords of the query")

def validate_training_data(data):
    examples = data.get("examples")
    if not examples:
        raise RuntimeError("Training data does not have examples member")
    attributes = inspect.getmembers(ExtractInfo, lambda x: not(inspect.isroutine(x)))
    model_fields = next(a for a in attributes if a[0] == "model_fields")
    required_attributes = model_fields[1].keys()
    for n, datum in enumerate(examples):
        if datum.keys() != required_attributes:
            raise RuntimeError(f"Example {n} has an incorrect schema: must have {list(required_attributes)} as members")

def load_training_data(file):
    with open(file, "r", encoding="utf8") as f:
        data = json.load(f)
    validate_training_data(data)
    return data

def train(model_client, training):
    dspy.settings.configure(lm=model_client)
    matcher = dspy.ReAct(ExtractInfo, tools=[])

    def validate_match(example, pred, trace=None):
        return pred.filters.keys() >= example.filters.keys()

    tp = dspy.MIPROv2(metric=validate_match, auto="light", prompt_model=model_client, task_model=model_client)
    return tp.compile(matcher, trainset=training, requires_permission_to_run=False)

def get_client(args):
    if args.client not in globals():
        raise RuntimeError(f"Invalid LLM client name: {args.client}")
    client_args = {}
    for arg in args.clientarg:
        bits = arg.split("=")
        if len(bits) != 2:
            raise RuntimeError(f"Invalid client arg: {arg}")
        client_args[bits[0]] = bits[1]
    return globals()[args.client](**client_args)

def argparser():
    argparser = argparse.ArgumentParser(description='Creates a saved prompt (from supplied examples) to extract metadata filters using a named LLM')
    argparser.add_argument('--inputfile', '-i', help='Path to examples training file', required=True)
    argparser.add_argument('--outputfile', '-o', help='Path to output file', required=True)
    argparser.add_argument('--client', '-c', help='LLM client class to use (VertexLLMClient or VLLMClient)', required=True)
    argparser.add_argument('--clientarg', '-a', nargs='+', help='args as key/value pairs to use for LLM client class (e.g. "model=mistralai/Mistral-7B-Instruct-v0.2"')
    return argparser

if __name__ == "__main__":
    args = argparser().parse_args()
    training_data = load_training_data(args.inputfile)
    trainset = [dspy.Example(**datum).with_inputs("text") for datum in training_data["examples"]]
    this_client = get_client(args)
    matcher = train(this_client, trainset)
    matcher.save(args.outputfile)