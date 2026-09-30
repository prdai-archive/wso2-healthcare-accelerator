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

"""Show the time the Jev pre-check saves versus what it costs.

Builds synthetic clinical notes at realistic lengths and runs the real policy
over each one twice: once with ``jev=False`` (OpenMed masks everything) and once
with ``jev=True`` (Jev decides whether to skip masking). Prints and plots the
per-request latency distribution, the OpenMed time avoided, the Jev time added,
and the Jev dollar cost.
"""

from __future__ import annotations

import importlib.util
import json
import statistics
import sys
import time
import types
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).parent
OUT_DIR = HERE / "experiment_results"
JEV_PRICE_PER_TOKEN = 0.042 / 1_000_000
SIZES = (1024, 2048, 4096)
REPEATS = 2
FILLER = "The patient tolerated the procedure well with stable vitals throughout recovery. "
PATIENTS = (
    "Referral for Alice Nguyen, MRN-4100137, DOB 1968-04-12, phone +1-555-0100. ",
    "Discharge for Marcus Bell, MRN-4100274, DOB 1975-11-02, email marcus.bell@example.com. ",
    "Pre-auth for Priya Raman, MRN-4100411, DOB 1990-07-23, insurance INS-4823-904. ",
)


def _load_policy_module() -> types.ModuleType:
    from unittest.mock import patch

    class _Modification:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)

    sdk = types.ModuleType("apip_sdk_core")
    for name in (
        "ImmediateResponse",
        "UpstreamRequestModifications",
        "DownstreamResponseModifications",
        "ProcessingMode",
        "BodyProcessingMode",
        "ExecutionContext",
        "RequestContext",
        "ResponseContext",
        "RequestAction",
        "ResponseAction",
    ):
        setattr(sdk, name, _Modification)
    sdk.RequestPolicy = type("RequestPolicy", (), {})
    sdk.ResponsePolicy = type("ResponsePolicy", (), {})

    module_path = HERE.parent / "src/pii_masking_v1/policy.py"
    spec = importlib.util.spec_from_file_location("pii_masking_v1.policy", module_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, {"apip_sdk_core": sdk}), patch("threading.Thread"):
        spec.loader.exec_module(module)
    return module


def _build_note(target_tokens: int, has_pii: bool, serial: int, encoding) -> str:
    unit = encoding.encode(FILLER)
    header = encoding.encode(PATIENTS[serial % len(PATIENTS)]) if has_pii else []
    repeats = max(1, (target_tokens - len(header)) // len(unit))
    body = FILLER * repeats
    return (PATIENTS[serial % len(PATIENTS)] + body) if has_pii else body


def _run_request(policy, request_id: str, text: str) -> float:
    body = json.dumps({"model": "gpt-4o-mini", "messages": [{"role": "user", "content": text}]}).encode()
    started = time.perf_counter()
    ctx = SimpleNamespace(
        shared=SimpleNamespace(request_id=request_id),
        body=SimpleNamespace(present=True, content=body),
    )
    action = policy.on_request_body(None, ctx, {})
    response_body = getattr(action, "body", None) or body
    rctx = SimpleNamespace(
        shared=SimpleNamespace(request_id=request_id),
        response_body=SimpleNamespace(present=True, content=response_body),
    )
    policy.on_response_body(None, rctx, {})
    return time.perf_counter() - started


def _plot(rows: list[dict[str, float]], path: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    without = [row["without_s"] for row in rows]
    with_jev = [row["with_s"] for row in rows]
    jev_total = sum(row["jev_s"] for row in rows)
    openmed_without = sum(without)
    openmed_with = sum(with_jev) - jev_total
    cost = sum(row["jev_cost_usd"] for row in rows)

    fig, axes = plt.subplots(1, 2, figsize=(13, 5))

    axes[0].boxplot([without, with_jev], tick_labels=["without Jev", "with Jev"], showfliers=False)
    for index, series in enumerate((without, with_jev), start=1):
        jitter = [index + (i % 5 - 2) * 0.03 for i in range(len(series))]
        axes[0].scatter(jitter, series, alpha=0.6, s=22, color=["#dd8452", "#4c72b0"][index - 1])
    axes[0].set_ylabel("seconds per request")
    axes[0].set_title("Per-request latency distribution")

    axes[1].bar(["without Jev", "with Jev"], [openmed_without, openmed_with], color="#dd8452", label="OpenMed")
    axes[1].bar(["with Jev"], [jev_total], bottom=[openmed_with], color="#4c72b0", label="Jev")
    axes[1].set_ylabel("seconds (total)")
    axes[1].set_title("Where the time goes")
    axes[1].legend()
    axes[1].text(
        0.5,
        -0.18,
        f"OpenMed time avoided: {openmed_without - openmed_with:.1f}s   "
        f"Jev time added: {jev_total:.1f}s   "
        f"net saved: {sum(without) - sum(with_jev):.1f}s   cost: ${cost:.4f}",
        ha="center",
        transform=axes[1].transAxes,
        fontsize=10,
    )

    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def main() -> None:
    import tiktoken

    if "--replot" in sys.argv:
        data = json.loads((OUT_DIR / "results.json").read_text(encoding="utf-8"))
        _plot(data["rows"], OUT_DIR / "time_saved.png")
        print(f"wrote {OUT_DIR / 'time_saved.png'}")
        return

    encoding = tiktoken.get_encoding("cl100k_base")
    module = _load_policy_module()
    off = module.PiiMaskingPolicy(jev=False)
    on = module.PiiMaskingPolicy(jev=True)
    off._redact_text("warm up", {})
    on._redact_text("warm up", {})

    rows: list[dict[str, float]] = []
    skipped = 0
    serial = 0
    for target in SIZES:
        for repeat in range(REPEATS):
            for has_pii in (True, False):
                serial += 1
                text = _build_note(target, has_pii, serial + repeat, encoding)
                without_s = _run_request(off, f"off-{serial}", text)
                with_s = _run_request(on, f"on-{serial}", text)
                decision = on.last_jev or {}
                if not decision.get("mask", True):
                    skipped += 1
                rows.append(
                    {
                        "tokens": len(encoding.encode(text)),
                        "has_pii": float(has_pii),
                        "without_s": without_s,
                        "with_s": with_s,
                        "jev_s": decision.get("latency_s", 0.0),
                        "probability": decision.get("probability") or 0.0,
                        "jev_cost_usd": decision.get("input_tokens", 0) * JEV_PRICE_PER_TOKEN,
                    }
                )
                print(f"{serial:2d} tok={len(encoding.encode(text)):5d} pii={has_pii} "
                      f"off={without_s:6.2f}s on={with_s:6.2f}s p={decision.get('probability')}", flush=True)

    summary = {
        "requests": len(rows),
        "skipped": skipped,
        "mean_without_s": statistics.mean(row["without_s"] for row in rows),
        "mean_with_s": statistics.mean(row["with_s"] for row in rows),
        "total_without_s": sum(row["without_s"] for row in rows),
        "total_with_s": sum(row["with_s"] for row in rows),
        "total_jev_s": sum(row["jev_s"] for row in rows),
        "total_cost_usd": sum(row["jev_cost_usd"] for row in rows),
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "results.json").write_text(json.dumps({"summary": summary, "rows": rows}, indent=2), encoding="utf-8")
    _plot(rows, OUT_DIR / "time_saved.png")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
