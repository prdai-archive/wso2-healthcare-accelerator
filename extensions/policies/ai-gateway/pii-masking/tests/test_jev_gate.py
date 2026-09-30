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

import unittest
from unittest.mock import patch

from test_policy import load_policy_module


class ResolveJevTest(unittest.TestCase):
    def test_default_is_off(self) -> None:
        policy_module = load_policy_module()
        self.assertFalse(policy_module._resolve_jev(None))
        self.assertFalse(policy_module._resolve_jev({}))

    def test_enabled_by_parameter(self) -> None:
        policy_module = load_policy_module()
        self.assertTrue(policy_module._resolve_jev({"jev": True}))
        self.assertTrue(policy_module._resolve_jev({"jev": "true"}))


class JevDecisionTest(unittest.TestCase):
    def test_masks_when_probability_is_high(self) -> None:
        policy_module = load_policy_module()
        with patch.object(policy_module, "_count_tokens", return_value=100), patch.object(
            policy_module, "_jev_pii_probability", return_value=(0.95, 500)
        ):
            decision = policy_module._jev_decision("text")
        self.assertTrue(decision["mask"])
        self.assertEqual(decision["input_tokens"], 500)

    def test_skips_when_probability_is_low(self) -> None:
        policy_module = load_policy_module()
        with patch.object(policy_module, "_count_tokens", return_value=100), patch.object(
            policy_module, "_jev_pii_probability", return_value=(0.02, 500)
        ):
            decision = policy_module._jev_decision("text")
        self.assertFalse(decision["mask"])

    def test_over_budget_masks_without_calling_jev(self) -> None:
        policy_module = load_policy_module()
        with patch.object(policy_module, "_count_tokens", return_value=40_000), patch.object(
            policy_module, "_jev_pii_probability"
        ) as probability:
            decision = policy_module._jev_decision("text")
        self.assertTrue(decision["mask"])
        self.assertEqual(decision["reason"], "over_budget")
        probability.assert_not_called()

    def test_jev_error_masks(self) -> None:
        policy_module = load_policy_module()
        with patch.object(policy_module, "_count_tokens", return_value=100), patch.object(
            policy_module, "_jev_pii_probability", side_effect=RuntimeError("boom")
        ):
            decision = policy_module._jev_decision("text")
        self.assertTrue(decision["mask"])
        self.assertEqual(decision["reason"], "jev_error")


class PolicyToggleTest(unittest.TestCase):
    def test_get_policy_reads_the_jev_parameter(self) -> None:
        policy_module = load_policy_module()
        self.assertTrue(policy_module.get_policy({}, {"jev": True})._jev)
        self.assertFalse(policy_module.get_policy({}, {})._jev)


if __name__ == "__main__":
    unittest.main()
