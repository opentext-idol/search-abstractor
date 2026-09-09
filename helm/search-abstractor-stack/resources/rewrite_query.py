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

from concurrent.futures import ThreadPoolExecutor, as_completed
from idolnifi import *

from collections import defaultdict
from dataclasses import dataclass
from functools import cached_property

import datetime
import json
import re

try:
    import dspy
    import requests
    import dateutil
except:
    from idolnifi import installPackage,PersistentPackageDirectory
    installPackage('dspy==3.0.4', packageDirectory=PersistentPackageDirectory)
    installPackage('requests==2.32.5', packageDirectory=PersistentPackageDirectory)
    installPackage('python-dateutil==2.9.0.post0', packageDirectory=PersistentPackageDirectory)
    
    import dspy
    import requests
    import dateutil

from dateutil import parser

class ExtractInfo(dspy.Signature):
    """Extract metadata filters (used to query a data index) and subject keywords from text. Keywords must not appear in extracted filters."""

    text: str = dspy.InputField()
    filters: dict[str, str] = dspy.OutputField(desc="a dictionary of filters extracted")
    subject: str = dspy.OutputField(desc="the subject keywords of the query")

@dataclass
class FieldInformation:
    field_types: dict[str, set[str]]
    type_fields: dict[str, list[str]]

    @classmethod
    def from_engine(cls, engine_url):
        #NB: this won't work if the engine is protected by OEM encryption.
        #Use the ACI request functionality in NiFi Python once it becomes available.
        #NB: specifying fieldtypes directly allows for easier parsing in the case results are coming from a DAH
        resp = requests.get(f"{engine_url}/a=gettagnames&typedetails=true&responseformat=simplejson&fieldtype=parametric,numeric,date")
        resp.raise_for_status()

        data = resp.json()
        fields = data["autnresponse"]["responsedata"].get("name", [])

        field_types = {field["$"]: set(field.get("@types", "").split(",")) for field in fields}
        type_fields = defaultdict(list)
        for field, types in field_types.items():
            for type_ in types:
                if type_:
                    type_fields[type_].append(field)

        return cls(field_types, dict(type_fields))

class QueryBuilder:
    def __init__(self, engine_url):
        self.engine_url = engine_url
        #Map filter names to field types - a filter with that name should be transformed into a fieldtext query against all fields of that type
        self.filter_mappings = {"author": "parametric",
                                "status": "parametric",
                                "number": "numeric",
                                "quantity": "numeric",
                                "amount": "numeric",
                                "opening_date": "date",
                                "date_from": "date",
                                "date_to": "date",
                                "date_range_start": "date",
                                "date_range_end": "date",
                                "date_start": "date",
                                "date_end": "date"}

        self.type_operators = {"parametric": "BIASVAL{{{value},10,2}}:{field}",
                                "numeric": "BIAS{{{value},5,10}}:{field}",
                                "numeric_range": "BIASNRANGE{{{value},5,5,10}}:{field}",
                                "date": "BIASRANGE{{{value},172800,172800,10}}:{field}",
                                "date_range": "BIASRANGE{{{value},172800,172800,10}}:{field}"}
    @cached_property
    def info(self):
        return FieldInformation.from_engine(self.engine_url)

    def _get_target_fields(self, field_type):
        return [field.split("/")[-1] for field in self.info.type_fields.get(field_type, [])]
    
    def to_query(self, query_filters):
        #Build the query from the subject and filters
        query_text = query_filters.subject
        all_fieldtext = []
        ranges = {}
        for filter_name, value in query_filters.filters.items():
            filter = None
            field_type = self.filter_mappings.get(filter_name)
            elements = filter_name.split("_")
            if elements[-1] in ["min", "max", "from", "to", "start", "end"]:
                #We have a range filter - store it for later
                range_bound = elements.pop(-1)
                filter = "_".join(elements)
                if field_type == "date":
                    try:
                        value = f"{int(parser.parse(value).timestamp())}e"
                    except parser.ParserError:
                        logInfo(f"Could not parse date value for filter {filter_name}: {value}")
                        continue
                if filter in ranges:
                    idx = 0 if range_bound in ["min", "from", "start"] else 1
                    ranges[filter].insert(idx, value)
                else:
                    ranges[filter] = [value]
                    continue
            field_type_lookup = f"{field_type}_range" if filter is not None else field_type
            fieldtext_template = self.type_operators.get(field_type_lookup)
            field_value = ",".join(ranges[filter]) if filter is not None else value
            if field_type == "date" and filter is None:
                #need to process this further
                try:
                    date_value = parser.parse(value)
                    next_day = date_value + datetime.timedelta(days=1)
                    field_value = f"{int(date_value.timestamp())}e,{int(next_day.timestamp())}e"
                except parser.ParserError:
                    logInfo(f"Could not parse date value for filter {filter_name}: {value}")
                    continue
            if field_type and fieldtext_template:
                target_fields = self._get_target_fields(field_type)
                all_fieldtext.append("(" + " OR ".join(fieldtext_template.format(value=field_value, field=field) for field in target_fields) + ")")
        
        return query_text, ' AND '.join(all_fieldtext)

def get_llm_client(props):
    model_impl = props.get("model.implementation", "VertexClient")
    model_cls = None
    from importlib import import_module
    if model_module := import_module(model_impl.lower()):
        model_cls = getattr(model_module, model_impl, None)
    if not model_cls:
        raise ImportError(f"Model client class {model_impl} not found")
    model_props = {k[len("model." + model_cls.propertyPrefix):]: v for k, v in props.items()}
    return model_cls.create_from_props(model_props)

class QueryRewriter:
    def __init__(self, loop_factor: int, prompt_file_path: str, engine_url: str, props: dict[str,str]):
        #Guard against dspy being configured multiple times
        if dspy.settings.get("lm") is None:
            dspy.settings.configure(lm=get_llm_client(props))

        self.matcher = dspy.ReAct(ExtractInfo, tools=[])
        self.matcher.load(path=prompt_file_path)
        self.builder = QueryBuilder(engine_url)
        #Try this many LLM calls to get query filters
        self.loop_factor = loop_factor
        self.filter_name_mappings = {"start_date": "date_start", "end_date": "date_end"}
        self.refusal_regexes = [r"none($|\s)", r"not found", r"no subject", r"n/a", r"\[\]$", r"this text does not contain", r"cannot provide", r"unable to extract", r"no relevant", r"no keywords", r"no filters", r"no terms"]
        self.refusal_patterns = r"^\s*(" + r"|".join(self.refusal_regexes) + r")"

    def check_for_refusals(self, subject: str) -> bool:
        return re.search(self.refusal_patterns, subject.lower()) is not None

    def rewrite(self, text: str):
        all_results = []

        def run_single_match():
            return self.matcher(text=text)

        max_workers = min(self.loop_factor, 8)

        #LLM calls can be expensive, so run in parallel for speed
        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = [pool.submit(run_single_match) for _ in range(self.loop_factor)]
            for future in as_completed(futures):
                try:
                    res = future.result()
                except Exception as e:
                    logWarn(f"Filter extraction attempt failed: {e}")
                    continue
                all_results.append(res)

        # Pick the attempt with the most filters
        if not all_results:
            return None, None
        query_filters = max(all_results, key=lambda x: len(getattr(x, 'filters', {})))
        logInfo(f"Extracted filters: {query_filters.filters}")
        #Map any filter names as needed before processing
        query_filters.filters = {self.filter_name_mappings.get(k, k): v for k, v in query_filters.filters.items()}
        if self.check_for_refusals(query_filters.subject):
            #LLM has refused to provide subject - go with the original text instead
            query_filters.subject = text
        return self.builder.to_query(query_filters)

def is_json(s):
    try:
        json.loads(s)
        return True
    except:
        return False

def handler(context, doc):
    properties = context.getProperties()
    enabled = properties.get(getPropertyDescriptor("Enabled"), "false") in ["true", "True", "TRUE"]
    if not enabled:
        return
    prompt_file_path = properties.get(getPropertyDescriptor("PromptFile"))
    if not prompt_file_path:
        logError("No prompt file path specified for query rewriting")
        return
    config_props = {desc.getName(): prop for desc, prop in properties.items() if desc.getName().startswith("model.")}
    engine_url = f"http://{properties.get(getPropertyDescriptor("IDOLServerHost"), "idol-query-service")}:{properties.get(getPropertyDescriptor("IDOLServerPort"), "9100")}"
    impl = QueryRewriter(loop_factor=4, prompt_file_path=prompt_file_path, engine_url=engine_url, props=config_props)
    with doc.updatingAttributes() as action:
        original_text = action.getAttribute("http.query.param.text")
        resource_id = action.getAttribute("http.query.param.resourceid")
        #resource_id presence means original_text is a vector rather than query text, so we skip rewriting
        if resource_id or not original_text:
            return
        logInfo(f"Original query text: {original_text}")
        query_text, fieldtext = impl.rewrite(original_text)
        logInfo(f"Rewrote query text: {original_text} -> {query_text} with fieldtext: {fieldtext}")
        if fieldtext:
            action.setAttribute("idol.query.rewrite.filters", fieldtext)
        if query_text and not is_json(query_text):
            action.setAttribute("idol.query.rewrite.text", query_text)