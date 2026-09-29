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

"""Decide whether a request needs PII masking, using Jev's probability.

The gate is a thin policy layer over Jev's `noul` answer: Jev returns the
probability that the text contains personal identifiers, and this module turns
that number into a mask/skip decision. It is deliberately biased toward
masking — only a confident "no PII" skips OpenMed, so an uncertain probability
masks. If the text would exceed Jev's state window we never call it and mask
unconditionally instead.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass

DEFAULT_MASK_THRESHOLD = 0.5
DEFAULT_SKIP_THRESHOLD = 0.2
STATE_TOKEN_BUDGET = 32_000
JEV_INPUT_USD_PER_MTOK = 0.042
DEFAULT_MODEL = "jev-latest"
DEFAULT_ENCODING = "cl100k_base"

QUESTION_INSTRUCTIONS = (
    "Does the text contain personally identifiable information (PII) about a "
    "specific individual — such as a name, medical record number, date of birth, "
    "phone number, email, address, or insurance identifier — that must be masked "
    "before the text leaves the organisation?"
)
QUESTION_CRITERIA = {
    "true": "Contains personal identifiers tied to a specific individual.",
    "false": "No personal identifiers; general clinical, administrative, or public information.",
}


@dataclass(frozen=True)
class JevResult:
    probability: float
    model: str | None
    input_tokens: int | None
    output_tokens: int | None
    latency_s: float


@dataclass(frozen=True)
class GateOutcome:
    should_mask: bool
    reason: str
    estimated_tokens: int
    probability: float | None = None
    jev_model: str | None = None
    jev_input_tokens: int | None = None
    jev_output_tokens: int | None = None
    jev_latency_s: float | None = None
    error: str | None = None

    @property
    def jev_cost_usd(self) -> float:
        if not self.jev_input_tokens:
            return 0.0
        return self.jev_input_tokens / 1_000_000 * JEV_INPUT_USD_PER_MTOK


def estimate_tokens(text: str, encoding_name: str = DEFAULT_ENCODING) -> int:
    import tiktoken

    return len(tiktoken.get_encoding(encoding_name).encode(text))


def decide(
    probability: float,
    mask_threshold: float = DEFAULT_MASK_THRESHOLD,
    skip_threshold: float = DEFAULT_SKIP_THRESHOLD,
) -> tuple[bool, str]:
    if probability <= skip_threshold:
        return False, "jev_low"
    if probability >= mask_threshold:
        return True, "jev_high"
    return True, "jev_uncertain"


def build_classifier(api_key: str | None = None) -> Callable[[str], JevResult]:
    from typesafe_sdk import Noul, TypeSafeClient

    client = TypeSafeClient(api_key=api_key)

    def classify(text: str) -> JevResult:
        started = time.perf_counter()
        response = client.system_one(
            state=text,
            model=DEFAULT_MODEL,
            questions={
                "needs_masking": Noul(
                    instructions=QUESTION_INSTRUCTIONS,
                    criteria=QUESTION_CRITERIA,
                )
            },
        )
        latency_s = time.perf_counter() - started
        answer = response.answers["needs_masking"]
        return JevResult(
            probability=float(answer.noul),
            model=response.model,
            input_tokens=response.usage.input_tokens,
            output_tokens=response.usage.output_tokens,
            latency_s=latency_s,
        )

    return classify


@dataclass
class JevGate:
    classifier: Callable[[str], JevResult]
    mask_threshold: float = DEFAULT_MASK_THRESHOLD
    skip_threshold: float = DEFAULT_SKIP_THRESHOLD
    token_budget: int = STATE_TOKEN_BUDGET
    estimate: Callable[[str], int] = estimate_tokens

    def evaluate(self, text: str, masking_enabled: bool = True) -> GateOutcome:
        if not masking_enabled:
            return GateOutcome(should_mask=False, reason="masking_disabled", estimated_tokens=0)

        estimated = self.estimate(text)
        if estimated + self.estimate(QUESTION_INSTRUCTIONS) > self.token_budget:
            return GateOutcome(should_mask=True, reason="over_budget", estimated_tokens=estimated)

        try:
            result = self.classifier(text)
        except Exception as exc:
            # Fail closed: an unclassifiable payload is masked rather than forwarded unmasked.
            return GateOutcome(
                should_mask=True,
                reason="jev_error",
                estimated_tokens=estimated,
                error=f"{type(exc).__name__}: {exc}",
            )

        should_mask, reason = decide(result.probability, self.mask_threshold, self.skip_threshold)
        return GateOutcome(
            should_mask=should_mask,
            reason=reason,
            estimated_tokens=estimated,
            probability=result.probability,
            jev_model=result.model,
            jev_input_tokens=result.input_tokens,
            jev_output_tokens=result.output_tokens,
            jev_latency_s=result.latency_s,
        )
