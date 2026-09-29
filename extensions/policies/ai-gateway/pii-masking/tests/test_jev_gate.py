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

import os
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from jev_gate import JevGate, JevResult, decide
from test_policy import load_policy_module


def _result(probability: float) -> JevResult:
    return JevResult(
        probability=probability,
        model="jev-test",
        input_tokens=100,
        output_tokens=10,
        latency_s=0.01,
    )


class DecideTest(unittest.TestCase):
    def test_low_probability_skips_masking(self) -> None:
        self.assertEqual(decide(0.05), (False, "jev_low"))

    def test_high_probability_masks(self) -> None:
        self.assertEqual(decide(0.99), (True, "jev_high"))

    def test_uncertain_probability_masks(self) -> None:
        self.assertEqual(decide(0.35), (True, "jev_uncertain"))

    def test_skip_boundary_is_inclusive(self) -> None:
        self.assertEqual(decide(0.2), (False, "jev_low"))

    def test_mask_boundary_is_inclusive(self) -> None:
        self.assertEqual(decide(0.5), (True, "jev_high"))


class GateTest(unittest.TestCase):
    def test_skips_classifier_when_masking_disabled(self) -> None:
        classifier = Mock()
        outcome = JevGate(classifier=classifier).evaluate("Alice Nguyen", masking_enabled=False)
        self.assertFalse(outcome.should_mask)
        self.assertEqual(outcome.reason, "masking_disabled")
        classifier.assert_not_called()

    def test_masks_without_classifier_when_over_budget(self) -> None:
        classifier = Mock()
        gate = JevGate(classifier=classifier, estimate=lambda _: 40_000)
        outcome = gate.evaluate("long note")
        self.assertTrue(outcome.should_mask)
        self.assertEqual(outcome.reason, "over_budget")
        self.assertEqual(outcome.estimated_tokens, 40_000)
        classifier.assert_not_called()

    def test_uses_probability_when_within_budget(self) -> None:
        gate = JevGate(classifier=lambda _: _result(0.98), estimate=lambda _: 50)
        outcome = gate.evaluate("Alice Nguyen")
        self.assertTrue(outcome.should_mask)
        self.assertEqual(outcome.reason, "jev_high")
        self.assertEqual(outcome.probability, 0.98)
        self.assertEqual(outcome.jev_input_tokens, 100)

    def test_low_probability_skips(self) -> None:
        gate = JevGate(classifier=lambda _: _result(0.01), estimate=lambda _: 50)
        outcome = gate.evaluate("Metformin 500 mg twice daily")
        self.assertFalse(outcome.should_mask)
        self.assertEqual(outcome.reason, "jev_low")

    def test_classifier_error_fails_closed(self) -> None:
        def explode(_: str) -> JevResult:
            raise RuntimeError("connection reset")

        outcome = JevGate(classifier=explode, estimate=lambda _: 20).evaluate("Alice Nguyen")
        self.assertTrue(outcome.should_mask)
        self.assertEqual(outcome.reason, "jev_error")
        self.assertIn("RuntimeError", outcome.error or "")

    def test_cost_is_input_tokens_per_million(self) -> None:
        gate = JevGate(classifier=lambda _: _result(0.9), estimate=lambda _: 1)
        outcome = gate.evaluate("Alice Nguyen")
        self.assertAlmostEqual(outcome.jev_cost_usd, 100 / 1_000_000 * 0.042)

    def test_no_tokens_means_no_cost(self) -> None:
        result = JevResult(
            probability=0.9, model=None, input_tokens=None, output_tokens=None, latency_s=0.0
        )
        gate = JevGate(classifier=lambda _: result, estimate=lambda _: 1)
        self.assertEqual(gate.evaluate("Alice Nguyen").jev_cost_usd, 0.0)


class EnabledToggleTest(unittest.TestCase):
    def test_parameter_takes_precedence_over_env(self) -> None:
        policy_module = load_policy_module()
        with patch.dict(os.environ, {"PII_MASKING_ENABLED": "true"}):
            self.assertFalse(policy_module._resolve_enabled({"enabled": False}))

    def test_env_fallback_used_when_parameter_absent(self) -> None:
        policy_module = load_policy_module()
        with patch.dict(os.environ, {"PII_MASKING_ENABLED": "false"}):
            self.assertFalse(policy_module._resolve_enabled({}))

    def test_default_enabled_true(self) -> None:
        policy_module = load_policy_module()
        with patch.dict(os.environ, {}, clear=True):
            self.assertTrue(policy_module._resolve_enabled(None))

    def test_disabled_policy_forwards_request_unchanged(self) -> None:
        policy_module = load_policy_module()
        policy = policy_module.PiiMaskingPolicy(enabled=False)
        ctx = SimpleNamespace(shared=SimpleNamespace(request_id="req-1"))
        self.assertIsNone(policy.on_request_body(Mock(), ctx, {}))
        self.assertIsNone(policy.on_response_body(Mock(), ctx, {}))

    def test_get_policy_reads_parameter(self) -> None:
        policy_module = load_policy_module()
        self.assertFalse(policy_module.get_policy({}, {"enabled": False})._enabled)
        self.assertTrue(policy_module.get_policy({}, {})._enabled)


if __name__ == "__main__":
    unittest.main()
