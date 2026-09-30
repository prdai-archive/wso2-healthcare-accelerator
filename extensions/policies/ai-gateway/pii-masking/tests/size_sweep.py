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

"""Measure Jev and OpenMed latency and cost as the input grows to 32k tokens.

One synthetic clinical note is built for each target size, with a real PII
header so OpenMed has something to find. Each size is measured once: the Jev
gate call, then the OpenMed mask-and-restore, so the per-request cost of each
component at that input length is recorded.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import tiktoken

from experiment_plots import plot_size_sweep
from jev_gate import JEV_INPUT_USD_PER_MTOK, build_classifier
from test_policy import load_policy_module

HERE = Path(__file__).parent
DEFAULT_OUT_DIR = HERE / "experiment_results"
SIZES = (32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 24576, 30976)
FILLER = "The patient tolerated the procedure well with stable vitals throughout recovery. "
HEADER = "Referral for Alice Nguyen, MRN-4100137, DOB 1968-04-12, phone +1-555-0100. "


def build_note(target_tokens: int, encoding) -> str:
    unit = encoding.encode(FILLER)
    header = encoding.encode(HEADER)
    repeats = max(1, (target_tokens - len(header)) // len(unit))
    return HEADER + FILLER * repeats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--sizes", type=int, nargs="+", default=list(SIZES))
    parser.add_argument("--replot", action="store_true", help="only regenerate the chart from size_sweep.json")
    args = parser.parse_args()

    if args.replot:
        data = json.loads((args.out_dir / "size_sweep.json").read_text(encoding="utf-8"))
        plot_size_sweep(data["rows"], args.out_dir / "latency_vs_size.png")
        print(f"wrote {args.out_dir / 'latency_vs_size.png'}")
        return

    encoding = tiktoken.get_encoding("cl100k_base")
    classify = build_classifier()
    policy = load_policy_module().PiiMaskingPolicy()
    policy._redact_text("warm up", {})

    rows: list[dict[str, float]] = []
    for target in args.sizes:
        text = build_note(target, encoding)
        tokens = len(encoding.encode(text))

        started = time.perf_counter()
        result = classify(text)
        jev_s = time.perf_counter() - started

        started = time.perf_counter()
        policy._redact_text(text, {})
        openmed_s = time.perf_counter() - started

        row = {
            "target": target,
            "tokens": tokens,
            "jev_s": jev_s,
            "openmed_s": openmed_s,
            "jev_input_tokens": result.input_tokens,
            "jev_cost_usd": (result.input_tokens or 0) / 1_000_000 * JEV_INPUT_USD_PER_MTOK,
        }
        rows.append(row)
        print(json.dumps(row), flush=True)

    window = [row for row in rows if 1024 <= row["tokens"] <= 32768]
    summary = {
        "sizes": len(rows),
        "window_sizes": len(window),
        "mean_jev_s": statistics.mean(row["jev_s"] for row in window),
        "mean_openmed_s": statistics.mean(row["openmed_s"] for row in window),
        "mean_jev_cost_usd": statistics.mean(row["jev_cost_usd"] for row in window),
        "max_tokens": max(row["tokens"] for row in rows),
    }

    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "size_sweep.json").write_text(
        json.dumps({"summary": summary, "rows": rows}, indent=2), encoding="utf-8"
    )
    plot_size_sweep(rows, args.out_dir / "latency_vs_size.png")
    print("summary:", json.dumps(summary))


if __name__ == "__main__":
    main()
