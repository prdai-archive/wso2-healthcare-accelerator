# Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License. You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import importlib.util
import sys
import types
from pathlib import Path
from unittest.mock import Mock, call, patch

import pytest


def load_policy_module() -> types.ModuleType:
    sdk = types.ModuleType("apip_sdk_core")
    for name in (
        "BodyProcessingMode",
        "DownstreamResponseModifications",
        "ExecutionContext",
        "ImmediateResponse",
        "ProcessingMode",
        "RequestAction",
        "RequestContext",
        "ResponseAction",
        "ResponseContext",
        "UpstreamRequestModifications",
    ):
        setattr(sdk, name, type(name, (), {}))
    sdk.RequestPolicy = type("RequestPolicy", (), {})
    sdk.ResponsePolicy = type("ResponsePolicy", (), {})

    with patch.dict(sys.modules, {"apip_sdk_core": sdk}), patch("threading.Thread"):
        module_path = Path(__file__).parents[1] / "src/pii_masking_v1/policy.py"
        spec = importlib.util.spec_from_file_location("pii_masking_v1.policy", module_path)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


class TestRestoreStructure:
    def test_restores_placeholder_in_object_key(self) -> None:
        policy_module = load_policy_module()
        policy = policy_module.PiiMaskingPolicy()
        mapping = {"<<OPENMED_PHI_NAME_000001>>": "Jane Doe"}

        with patch.object(policy, "_restore_text", side_effect=lambda text, _: mapping.get(text, text)):
            restored = policy._restore_structure({"<<OPENMED_PHI_NAME_000001>>": "summary"}, mapping)

        assert restored == {"Jane Doe": "summary"}


class TestPipelineCache:
    def test_reuses_the_loaded_privacy_filter_pipeline(self) -> None:
        policy_module = load_policy_module()
        backend = types.ModuleType("openmed.core.backends")
        backend.create_privacy_filter_pipeline = Mock(return_value=object())

        with patch.dict(
            sys.modules,
            {
                "openmed": types.ModuleType("openmed"),
                "openmed.core": types.ModuleType("openmed.core"),
                "openmed.core.backends": backend,
            },
        ):
            first = policy_module._privacy_filter_pipeline()
            second = policy_module._privacy_filter_pipeline()

        assert first is second
        backend.create_privacy_filter_pipeline.assert_called_once_with(policy_module.MODEL_NAME)

    def test_keeps_a_pipeline_per_model(self) -> None:
        policy_module = load_policy_module()
        backend = types.ModuleType("openmed.core.backends")
        backend.create_privacy_filter_pipeline = Mock(side_effect=[object(), object()])

        with patch.dict(
            sys.modules,
            {
                "openmed": types.ModuleType("openmed"),
                "openmed.core": types.ModuleType("openmed.core"),
                "openmed.core.backends": backend,
            },
        ):
            first = policy_module._privacy_filter_pipeline("model-a")
            second = policy_module._privacy_filter_pipeline("model-b")

        assert first is not second
        assert backend.create_privacy_filter_pipeline.call_args_list == [call("model-a"), call("model-b")]


class TestRequestRedactionScope:
    def test_redacts_all_request_content_and_tool_metadata(self) -> None:
        policy_module = load_policy_module()
        policy = policy_module.PiiMaskingPolicy()
        redacted = []

        def redact_text(value, mapping):
            redacted.append(value)
            return f"redacted:{value}"

        with patch.object(policy, "_redact_text", side_effect=redact_text):
            result = policy._redact_structure(
                {
                    "tools": [
                        {
                            "type": "function",
                            "function": {
                                "name": "read_fhir",
                                "description": "Read records for Jane Doe",
                            },
                        }
                    ],
                    "messages": [
                        {"role": "system", "content": "Jane Doe system instructions"},
                        {"role": "developer", "content": "Jane Doe developer instructions"},
                        {"role": "user", "content": "Jane Doe"},
                    ]
                },
                {},
            )

        assert result["messages"][0]["content"] == "redacted:Jane Doe system instructions"
        assert result["messages"][1]["content"] == "redacted:Jane Doe developer instructions"
        assert result["messages"][2]["content"] == "redacted:Jane Doe"
        assert result["tools"][0]["function"]["description"] == "redacted:Read records for Jane Doe"
        assert "Read records for Jane Doe" in redacted

    def test_preserves_tool_call_protocol_identifiers(self) -> None:
        policy_module = load_policy_module()
        policy = policy_module.PiiMaskingPolicy()

        with patch.object(policy, "_redact_text", side_effect=lambda value, _: f"redacted:{value}"):
            result = policy._redact_structure(
                {
                    "messages": [
                        {
                            "role": "assistant",
                            "tool_calls": [
                                {
                                    "id": "call_FkfMPkwPsvW7CBExEySfLGEQ",
                                    "type": "function",
                                    "function": {
                                        "name": "search_fhir",
                                        "arguments": '{"name":"Jane Doe"}',
                                    },
                                }
                            ],
                        },
                        {
                            "role": "tool",
                            "tool_call_id": "call_FkfMPkwPsvW7CBExEySfLGEQ",
                            "content": "Jane Doe patient record",
                        },
                    ]
                },
                {},
            )

        tool_call = result["messages"][0]["tool_calls"][0]
        assert tool_call["id"] == "call_FkfMPkwPsvW7CBExEySfLGEQ"
        assert tool_call["type"] == "function"
        assert tool_call["function"]["name"] == "search_fhir"
        assert tool_call["function"]["arguments"] == 'redacted:{"name":"Jane Doe"}'
        assert result["messages"][1]["tool_call_id"] == "call_FkfMPkwPsvW7CBExEySfLGEQ"
        assert result["messages"][1]["content"] == "redacted:Jane Doe patient record"
