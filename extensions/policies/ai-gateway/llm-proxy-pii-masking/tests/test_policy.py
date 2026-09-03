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
import unittest
from pathlib import Path
from unittest.mock import patch


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
        module_path = Path(__file__).parents[1] / "src/pii_masking_v0/policy.py"
        spec = importlib.util.spec_from_file_location("pii_masking_v0.policy", module_path)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


class RestoreStructureTest(unittest.TestCase):
    def test_restores_placeholder_in_object_key(self) -> None:
        policy_module = load_policy_module()
        policy = policy_module.PiiMaskingPolicy()
        mapping = {"<<OPENMED_PHI_NAME_000001>>": "Jane Doe"}

        with patch.object(policy, "_restore_text", side_effect=lambda text, _: mapping.get(text, text)):
            restored = policy._restore_structure({"<<OPENMED_PHI_NAME_000001>>": "summary"}, mapping)

        self.assertEqual(restored, {"Jane Doe": "summary"})
