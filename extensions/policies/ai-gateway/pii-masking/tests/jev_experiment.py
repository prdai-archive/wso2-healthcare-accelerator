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
REQUESTS = HERE / "requests.json"
PLOT = HERE / "jev_experiment.png"
JEV_PRICE_PER_TOKEN = 0.042 / 1_000_000


def load_policy_module() -> types.ModuleType:
    from unittest.mock import patch

    class Modification:
        def __init__(self, **kwargs) -> None:
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
        setattr(sdk, name, Modification)
    sdk.RequestPolicy = type("RequestPolicy", (), {})
    sdk.ResponsePolicy = type("ResponsePolicy", (), {})

    path = HERE.parent / "src/pii_masking_v1/policy.py"
    spec = importlib.util.spec_from_file_location("pii_masking_v1.policy", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, {"apip_sdk_core": sdk}), patch("threading.Thread"):
        spec.loader.exec_module(module)
    return module


def run_request(policy, request_id: str, text: str) -> float:
    body = json.dumps({"model": "gpt-4o-mini", "messages": [{"role": "user", "content": text}]}).encode()
    started = time.perf_counter()
    ctx = SimpleNamespace(
        shared=SimpleNamespace(request_id=request_id),
        body=SimpleNamespace(present=True, content=body),
    )
    action = policy.on_request_body(None, ctx, {})
    rctx = SimpleNamespace(
        shared=SimpleNamespace(request_id=request_id),
        response_body=SimpleNamespace(present=True, content=getattr(action, "body", None) or body),
    )
    policy.on_response_body(None, rctx, {})
    return time.perf_counter() - started


def plot(rows: list[dict], path: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    without = [row["without_s"] for row in rows]
    with_jev = [row["with_s"] for row in rows]
    jev_total = sum(row["jev_s"] for row in rows)
    openmed_without = sum(without)
    openmed_with = sum(with_jev) - jev_total
    cost = sum(row["cost_usd"] for row in rows)

    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    axes[0].boxplot([without, with_jev], tick_labels=["without Jev", "with Jev"], showfliers=False)
    for position, series in enumerate((without, with_jev), start=1):
        axes[0].scatter([position + (i % 5 - 2) * 0.03 for i in range(len(series))], series, alpha=0.6, s=22)
    axes[0].set_ylabel("seconds per request")
    axes[0].set_title("Per-request latency distribution")

    axes[1].bar(["without Jev", "with Jev"], [openmed_without, openmed_with], color="#dd8452", label="OpenMed")
    axes[1].bar(["with Jev"], [jev_total], bottom=[openmed_with], color="#4c72b0", label="Jev")
    axes[1].set_ylabel("seconds (total)")
    axes[1].set_title("Where the time goes")
    axes[1].legend()
    fig.text(
        0.5,
        0.01,
        f"OpenMed avoided {openmed_without - openmed_with:.1f}s | Jev added {jev_total:.1f}s | "
        f"net saved {openmed_without - openmed_with - jev_total:.1f}s | cost ${cost:.4f}",
        ha="center",
        fontsize=11,
    )
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    fig.savefig(path, dpi=150)
    plt.close(fig)


def main() -> None:
    requests = json.loads(REQUESTS.read_text(encoding="utf-8"))
    module = load_policy_module()
    off = module.PiiMaskingPolicy(jev=False)
    on = module.PiiMaskingPolicy(jev=True)
    off._redact_text("warm up", {})
    on._redact_text("warm up", {})

    rows = []
    for index, request in enumerate(requests, start=1):
        without_s = run_request(off, f"off-{index}", request["text"])
        with_s = run_request(on, f"on-{index}", request["text"])
        decision = on.last_jev or {}
        rows.append(
            {
                "has_pii": request["has_pii"],
                "mask": decision.get("mask", True),
                "without_s": without_s,
                "with_s": with_s,
                "jev_s": decision.get("latency_s", 0.0),
                "cost_usd": decision.get("input_tokens", 0) * JEV_PRICE_PER_TOKEN,
            }
        )
        print(f"[{index:2d}/{len(requests)}] pii={request['has_pii']} "
              f"off={without_s:6.2f}s on={with_s:6.2f}s p={decision.get('probability')}", flush=True)

    missed = [row for row in rows if row["has_pii"] and not row["mask"]]
    needless = [row for row in rows if not row["has_pii"] and row["mask"]]
    skipped = sum(not row["mask"] for row in rows)
    assert not missed, f"gate skipped {len(missed)} PII requests"

    plot(rows, PLOT)
    print(f"\ngate: skipped {skipped} requests, {len(needless)} needless masks, {len(missed)} missed PII")
    print(f"latency: without {statistics.mean(row['without_s'] for row in rows):.2f}s "
          f"vs with {statistics.mean(row['with_s'] for row in rows):.2f}s per request")
    print(f"wrote {PLOT}")


if __name__ == "__main__":
    main()
