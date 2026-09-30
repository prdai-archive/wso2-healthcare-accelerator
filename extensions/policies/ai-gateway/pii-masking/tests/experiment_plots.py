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

"""Plain-language charts for the Jev gate experiment, focused on time and cost.

`time_and_cost.png` is the headline: total time split into Jev and OpenMed for
each mode, the per-note latency of each component, and the Jev dollar cost. The
decision matrix is kept as a one-glance accuracy check that the gate is safe to
use at all.
"""

from __future__ import annotations

import math
import statistics
from pathlib import Path
from typing import Any

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

MODES = ("without_jev", "with_jev")
MODE_LABELS = {"without_jev": "without Jev\n(mask everything)", "with_jev": "with Jev\n(gate)"}
CORRECT_COLOR = "#d9f0d3"
ERROR_COLOR = "#f7c9c9"
JEV_COLOR = "#4c72b0"
OPENMED_COLOR = "#dd8452"
COST_SCALE_NOTES = (1_000, 10_000, 1_000_000)


def _request_latencies(outcomes: list[dict[str, Any]], masked: bool | None = None) -> list[float]:
    return [
        o["gate_latency_s"] + o["mask_latency_s"] + o["demask_latency_s"]
        for o in outcomes
        if masked is None or o["masked"] == masked
    ]


def _openmed_only(outcomes: list[dict[str, Any]]) -> list[float]:
    return [o["mask_latency_s"] + o["demask_latency_s"] for o in outcomes if o["masked"]]


def _mean_ms(values: list[float]) -> float:
    return statistics.mean(values) * 1000 if values else 0.0


def _p95_ms(values: list[float]) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))] * 1000


def plot_time_and_cost(
    summaries: dict[str, dict[str, Any]],
    outcomes: dict[str, list[dict[str, Any]]],
    path: Path,
) -> None:
    without = _request_latencies(outcomes["without_jev"])
    skipped = _request_latencies(outcomes["with_jev"], masked=False)
    masked = _request_latencies(outcomes["with_jev"], masked=True)
    openmed_masked = _openmed_only(outcomes["with_jev"])

    jev_only = _mean_ms(skipped)
    jev_with_openmed = _mean_ms(masked) - _mean_ms(openmed_masked)

    fig, axes = plt.subplots(1, 2, figsize=(13, 5))

    labels = ["without Jev\n(all requests)", "with Jev\n(no PII: skip)", "with Jev\n(has PII: mask)"]
    jev = [0.0, jev_only, jev_with_openmed]
    openmed = [_mean_ms(without), 0.0, _mean_ms(openmed_masked)]
    axes[0].bar(labels, jev, color=JEV_COLOR, label="Jev gate")
    axes[0].bar(labels, openmed, bottom=jev, color=OPENMED_COLOR, label="OpenMed mask + restore")
    for index in range(3):
        total = jev[index] + openmed[index]
        axes[0].text(index, total + 12, f"{total:.0f} ms", ha="center", fontsize=10)
    tail = [_p95_ms(group) for group in (without, skipped, masked)]
    for index, p95 in enumerate(tail):
        axes[0].plot([index - 0.34, index + 0.34], [p95, p95], color="#222222", linewidth=1.5)
    axes[0].plot([], [], color="#222222", linewidth=1.5, label="p95")
    axes[0].set_ylim(0, max(tail) * 1.25)
    axes[0].set_title("Time per request")
    axes[0].set_ylabel("milliseconds")
    axes[0].legend()

    per_request = summaries["with_jev"]["jev_cost_usd"] / summaries["with_jev"]["records"]
    bars = axes[1].bar(["without Jev", "with Jev"], [0.0, per_request], color=[OPENMED_COLOR, JEV_COLOR])
    axes[1].bar_label(bars, padding=2, fmt="$%.6f")
    axes[1].set_title("Jev cost per request (OpenMed is self-hosted: $0)")
    axes[1].set_ylabel("USD")
    axes[1].text(
        1,
        per_request * 0.5,
        "\n".join(f"${per_request * count:,.2f} per {count:,} requests" for count in COST_SCALE_NOTES),
        ha="center",
        va="top",
        fontsize=9,
        color="#444444",
    )

    fig.suptitle("Per-request time and cost: with Jev vs without Jev")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def plot_decision_matrices(summaries: dict[str, dict[str, Any]], path: Path) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.5))
    for ax, mode in zip(axes, MODES):
        summary = summaries[mode]
        counts = [
            [summary["gate_tp"], summary["gate_fn"]],
            [summary["gate_fp"], summary["gate_tn"]],
        ]
        notes = [["correct", "gate missed PII"], ["needless mask", "correct"]]
        shades = [
            [CORRECT_COLOR, ERROR_COLOR],
            [ERROR_COLOR, CORRECT_COLOR],
        ]
        for row in range(2):
            for col in range(2):
                ax.add_patch(
                    Rectangle((col - 0.5, row - 0.5), 1, 1, facecolor=shades[row][col], edgecolor="white")
                )
                ax.text(col, row - 0.05, str(counts[row][col]), ha="center", va="center", fontsize=22)
                ax.text(col, row + 0.26, notes[row][col], ha="center", va="center", fontsize=9, color="#666666")
        ax.set_xlim(-0.5, 1.5)
        ax.set_ylim(1.5, -0.5)
        ax.set_xticks([0, 1], ["Masked", "Skipped"])
        ax.set_yticks([0, 1], ["Has PII", "No PII"])
        ax.set_title(MODE_LABELS[mode].replace("\n", " "))
    fig.suptitle("Did the gate decide correctly? (100 notes)")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def _latency_crossover(tokens: list[float], jev: list[float], openmed: list[float]) -> float | None:
    for index in range(1, len(tokens)):
        was_slower = openmed[index - 1] > jev[index - 1]
        now_faster = openmed[index] > jev[index]
        if was_slower or not now_faster:
            continue
        low, high = math.log(tokens[index - 1]), math.log(tokens[index])
        before, after = openmed[index - 1] - jev[index - 1], openmed[index] - jev[index]
        if before == after:
            return tokens[index]
        fraction = before / (before - after)
        return math.exp(low + fraction * (high - low))
    return None


def plot_size_sweep(rows: list[dict[str, float]], path: Path) -> None:
    tokens = [row["tokens"] for row in rows]
    jev = [row["jev_s"] for row in rows]
    openmed = [row["openmed_s"] for row in rows]
    combined = [jev_s + openmed_s for jev_s, openmed_s in zip(jev, openmed)]
    cost = [row["jev_cost_usd"] for row in rows]

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    axes[0].plot(tokens, openmed, "o-", color=OPENMED_COLOR, label="without Jev: OpenMed only")
    axes[0].plot(tokens, combined, "s--", color="#8172b3", label="with Jev, has PII: Jev + OpenMed")
    axes[0].plot(tokens, jev, "^-", color=JEV_COLOR, label="with Jev, no PII: Jev only")
    axes[0].set_xscale("log")
    axes[0].set_yscale("log")
    crossover = _latency_crossover(tokens, jev, openmed)
    if crossover:
        axes[0].axvline(crossover, color="#999999", linestyle=":", linewidth=1)
        axes[0].text(crossover * 1.1, axes[0].get_ylim()[1], f"crossover ~{crossover:.0f} tok", va="top", fontsize=9)
    axes[0].set_xlabel("input tokens")
    axes[0].set_ylabel("seconds per request (log)")
    axes[0].set_title("Latency vs input size")
    axes[0].legend(loc="upper left")

    axes[1].plot(tokens, cost, "o-", color=JEV_COLOR)
    window = [row for row in rows if row["tokens"] >= 1024]
    mean_cost = statistics.mean(row["jev_cost_usd"] for row in window)
    axes[1].axhline(mean_cost, color="#999999", linestyle=":")
    axes[1].text(
        tokens[0],
        mean_cost,
        f" mean over 1k-32k: ${mean_cost:.6f}",
        va="bottom",
        fontsize=9,
        color="#666666",
    )
    axes[1].set_xlabel("input tokens")
    axes[1].set_ylabel("Jev cost per request (USD)")
    axes[1].set_title("Jev cost vs input size")

    fig.suptitle("Jev vs OpenMed as the input grows to 32k tokens")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def write_plots(
    summaries: dict[str, dict[str, Any]],
    outcomes: dict[str, list[dict[str, Any]]],
    out_dir: Path,
) -> None:
    plot_time_and_cost(summaries, outcomes, out_dir / "time_and_cost.png")
    plot_decision_matrices(summaries, out_dir / "decision_matrix.png")
