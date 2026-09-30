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

"""Run the synthetic clinical-note dataset through the two masking modes.

`without_jev` always masks every record; `with_jev` asks Jev whether the record
holds personal identifiers and only masks when it does (or when the record is
too large to classify). The runner records per-record decisions, Jev token
usage and cost, and wall-clock timing, then writes a results JSON and two
comparison plots.
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from experiment_plots import write_plots
from jev_gate import (
    DEFAULT_ENCODING,
    DEFAULT_MASK_THRESHOLD,
    DEFAULT_MODEL,
    DEFAULT_SKIP_THRESHOLD,
    STATE_TOKEN_BUDGET,
    JevGate,
    build_classifier,
    estimate_tokens,
)
from test_policy import load_policy_module

HERE = Path(__file__).parent
DEFAULT_DATASET = HERE / "clinical_notes.jsonl"
DEFAULT_OUT_DIR = HERE / "experiment_results"
PAYLOAD_MODEL = "gpt-4o-mini"
MODES = ("without_jev", "with_jev")
# The policy feeds each string to OpenMed whole; it has no chunking, so long
# inputs are out of scope for this experiment and recorded as unmasked.
OPENMED_MAX_INPUT_TOKENS = 2048


@dataclass
class RecordOutcome:
    record_id: str
    mode: str
    has_pii: bool
    masked: bool
    reason: str
    leaked_entities: list[str]
    roundtrip_ok: bool
    probability: float | None
    estimated_tokens: int
    jev_input_tokens: int
    jev_output_tokens: int
    jev_cost_usd: float
    gate_latency_s: float
    mask_latency_s: float
    demask_latency_s: float
    wall_latency_s: float
    mask_error: str | None


def _payload(text: str) -> dict[str, Any]:
    return {"model": PAYLOAD_MODEL, "messages": [{"role": "user", "content": text}]}


def _load_records(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _redacted_text(redacted: Any) -> str:
    return json.dumps(redacted, ensure_ascii=False)


def _run_masked(policy: Any, payload: dict[str, Any], entities: list[str], text_tokens: int) -> tuple[
    list[str], bool, float, float, str | None
]:
    if text_tokens > OPENMED_MAX_INPUT_TOKENS:
        return [], True, 0.0, 0.0, f"input exceeds openmed window ({text_tokens} tokens), masking skipped"

    mapping: dict[str, str] = {}
    mask_started = time.perf_counter()
    try:
        redacted = policy._redact_structure(payload, mapping)
    except Exception as exc:
        return list(entities), False, time.perf_counter() - mask_started, 0.0, f"{type(exc).__name__}: {exc}"
    mask_latency = time.perf_counter() - mask_started

    leaked = [entity for entity in entities if entity and entity in _redacted_text(redacted)]

    demask_started = time.perf_counter()
    restored = policy._restore_structure(redacted, mapping)
    demask_latency = time.perf_counter() - demask_started
    return leaked, restored == payload, mask_latency, demask_latency, None


def _evaluate_record(
    policy: Any,
    gate: JevGate,
    record: dict[str, Any],
    mode: str,
    masking_enabled: bool,
) -> RecordOutcome:
    started = time.perf_counter()
    payload = _payload(record["text"])
    entities: list[str] = record["entities"]
    text_tokens = gate.estimate(record["text"])

    if mode == "without_jev":
        masked = masking_enabled
        gate_latency = 0.0
        probability = None
        estimated = 0
        jev_input = jev_output = 0
        jev_cost = 0.0
        reason = "always" if masking_enabled else "masking_disabled"
    else:
        outcome = gate.evaluate(record["text"], masking_enabled=masking_enabled)
        masked = outcome.should_mask
        gate_latency = outcome.jev_latency_s or 0.0
        probability = outcome.probability
        estimated = outcome.estimated_tokens
        jev_input = outcome.jev_input_tokens or 0
        jev_output = outcome.jev_output_tokens or 0
        jev_cost = outcome.jev_cost_usd
        reason = outcome.reason

    if masked:
        leaked, roundtrip_ok, mask_latency, demask_latency, mask_error = _run_masked(
            policy, payload, entities, text_tokens
        )
    else:
        leaked, roundtrip_ok, mask_latency, demask_latency, mask_error = list(entities), True, 0.0, 0.0, None

    return RecordOutcome(
        record_id=record["id"],
        mode=mode,
        has_pii=record["has_pii"],
        masked=masked,
        reason=reason,
        leaked_entities=leaked,
        roundtrip_ok=roundtrip_ok,
        probability=probability,
        estimated_tokens=estimated,
        jev_input_tokens=jev_input,
        jev_output_tokens=jev_output,
        jev_cost_usd=jev_cost,
        gate_latency_s=gate_latency,
        mask_latency_s=mask_latency,
        demask_latency_s=demask_latency,
        wall_latency_s=time.perf_counter() - started,
        mask_error=mask_error,
    )


def _summarize(outcomes: list[RecordOutcome]) -> dict[str, Any]:
    pii = [o for o in outcomes if o.has_pii]
    non_pii = [o for o in outcomes if not o.has_pii]
    reasons: dict[str, int] = {}
    for outcome in outcomes:
        reasons[outcome.reason] = reasons.get(outcome.reason, 0) + 1

    return {
        "records": len(outcomes),
        "records_masked": sum(o.masked for o in outcomes),
        "records_skipped": sum(not o.masked for o in outcomes),
        "pii_total": len(pii),
        "pii_caught": sum(o.masked and not o.leaked_entities for o in pii),
        "pii_missed": sum((not o.masked) or bool(o.leaked_entities) for o in pii),
        "non_pii_total": len(non_pii),
        "non_pii_masked": sum(o.masked for o in non_pii),
        "non_pii_skipped": sum(not o.masked for o in non_pii),
        "gate_tp": sum(o.masked and o.has_pii for o in outcomes),
        "gate_fp": sum(o.masked and not o.has_pii for o in outcomes),
        "gate_tn": sum(not o.masked and not o.has_pii for o in outcomes),
        "gate_fn": sum(not o.masked and o.has_pii for o in outcomes),
        "entities_leaked": sum(len(o.leaked_entities) for o in outcomes),
        "roundtrip_failures": sum(o.masked and not o.roundtrip_ok for o in outcomes),
        "mask_errors": sum(o.mask_error is not None for o in outcomes),
        "jev_calls": sum(1 for o in outcomes if o.jev_input_tokens),
        "jev_input_tokens": sum(o.jev_input_tokens for o in outcomes),
        "jev_output_tokens": sum(o.jev_output_tokens for o in outcomes),
        "jev_cost_usd": sum(o.jev_cost_usd for o in outcomes),
        "gate_latency_s": sum(o.gate_latency_s for o in outcomes),
        "mask_latency_s": sum(o.mask_latency_s for o in outcomes),
        "demask_latency_s": sum(o.demask_latency_s for o in outcomes),
        "wall_latency_s": sum(o.wall_latency_s for o in outcomes),
        "reasons": reasons,
    }


def _warm_up(policy: Any, gate: JevGate, masking_enabled: bool) -> None:
    if not masking_enabled:
        return
    try:
        policy._redact_text("warm up", {})
    except Exception as exc:
        print(f"openmed warm-up failed: {type(exc).__name__}: {exc}")
    try:
        gate.classifier("warm up")
    except Exception as exc:
        print(f"jev warm-up failed: {type(exc).__name__}: {exc}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--limit", type=int, default=None, help="only run the first N records")
    parser.add_argument("--masking", choices=("on", "off"), default="on")
    parser.add_argument("--mask-threshold", type=float, default=DEFAULT_MASK_THRESHOLD)
    parser.add_argument("--skip-threshold", type=float, default=DEFAULT_SKIP_THRESHOLD)
    parser.add_argument("--token-budget", type=int, default=STATE_TOKEN_BUDGET)
    parser.add_argument("--encoding", default=DEFAULT_ENCODING)
    parser.add_argument("--no-plot", action="store_true")
    parser.add_argument("--replot", action="store_true", help="only regenerate plots from results.json")
    args = parser.parse_args()

    if args.replot:
        result = json.loads((args.out_dir / "results.json").read_text(encoding="utf-8"))
        write_plots(result["modes"], result["outcomes"], args.out_dir)
        print(f"wrote plots to {args.out_dir}")
        return

    records = _load_records(args.dataset)
    if args.limit:
        records = records[: args.limit]

    masking_enabled = args.masking == "on"
    policy = load_policy_module().PiiMaskingPolicy(enabled=masking_enabled)
    gate = JevGate(
        classifier=build_classifier(),
        mask_threshold=args.mask_threshold,
        skip_threshold=args.skip_threshold,
        token_budget=args.token_budget,
        estimate=lambda text: estimate_tokens(text, args.encoding),
    )

    print(f"running {len(records)} records, masking={args.masking}, model={DEFAULT_MODEL}")
    _warm_up(policy, gate, masking_enabled)
    outcomes: dict[str, list[RecordOutcome]] = {mode: [] for mode in MODES}
    for mode in MODES:
        for index, record in enumerate(records, start=1):
            outcomes[mode].append(_evaluate_record(policy, gate, record, mode, masking_enabled))
            if index % 10 == 0 or index == len(records):
                print(f"[{mode} {index}/{len(records)}]", flush=True)

    summaries = {mode: _summarize(outcomes[mode]) for mode in MODES}
    config = {
        "dataset": str(args.dataset),
        "records": len(records),
        "model": DEFAULT_MODEL,
        "masking_enabled": masking_enabled,
        "mask_threshold": args.mask_threshold,
        "skip_threshold": args.skip_threshold,
        "token_budget": args.token_budget,
        "encoding": args.encoding,
    }
    result = {
        "config": config,
        "modes": summaries,
        "outcomes": {mode: [asdict(o) for o in outcomes[mode]] for mode in MODES},
    }

    args.out_dir.mkdir(parents=True, exist_ok=True)
    results_path = args.out_dir / "results.json"
    results_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"wrote {results_path}")

    for mode in MODES:
        summary = summaries[mode]
        print(
            f"{mode}: masked={summary['records_masked']} skipped={summary['records_skipped']} "
            f"pii_missed={summary['pii_missed']} non_pii_masked={summary['non_pii_masked']} "
            f"jev_tokens={summary['jev_input_tokens']}/{summary['jev_output_tokens']} "
            f"jev_cost=${summary['jev_cost_usd']:.6f} time={summary['wall_latency_s']:.1f}s"
        )

    if not args.no_plot:
        write_plots(summaries, {mode: [asdict(o) for o in outcomes[mode]] for mode in MODES}, args.out_dir)
        print(f"wrote plots to {args.out_dir}")


if __name__ == "__main__":
    main()
