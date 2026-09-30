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
NOTES = 100


def _openmed_seconds(summary: dict[str, Any]) -> float:
    return summary["mask_latency_s"] + summary["demask_latency_s"]


def plot_time_and_cost(summaries: dict[str, dict[str, Any]], path: Path) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(16, 5))
    labels = [MODE_LABELS[mode] for mode in MODES]

    jev = [summaries[mode]["gate_latency_s"] for mode in MODES]
    openmed = [_openmed_seconds(summaries[mode]) for mode in MODES]
    axes[0].bar(labels, jev, color=JEV_COLOR, label="Jev gate (remote)")
    axes[0].bar(labels, openmed, bottom=jev, color=OPENMED_COLOR, label="OpenMed mask + restore")
    for index, mode in enumerate(MODES):
        total = jev[index] + openmed[index]
        axes[0].text(index, total + 0.6, f"{total:.1f}s total", ha="center", fontsize=10)
    axes[0].text(0, jev[0] + openmed[0] / 2, f"{openmed[0]:.1f}s", ha="center", color="white")
    axes[0].text(1, jev[1] / 2, f"{jev[1]:.1f}s Jev", ha="center", color="white")
    axes[0].text(1, jev[1] + openmed[1] / 2, f"{openmed[1]:.1f}s", ha="center", color="white")
    axes[0].set_ylim(0, max(jev[index] + openmed[index] for index in range(2)) * 1.2)
    axes[0].set_title("Time to process 100 notes")
    axes[0].set_ylabel("seconds")
    axes[0].legend()

    per_note_openmed = summaries["without_jev"]["mask_latency_s"] / NOTES * 1000
    per_note_jev = summaries["with_jev"]["gate_latency_s"] / summaries["with_jev"]["jev_calls"] * 1000
    bars = axes[1].bar(
        ["OpenMed mask\n(in-process)", "Jev gate\n(one remote call)"],
        [per_note_openmed, per_note_jev],
        color=[OPENMED_COLOR, JEV_COLOR],
    )
    axes[1].bar_label(bars, padding=2, fmt="%.0f ms")
    axes[1].set_title("Time per note")
    axes[1].set_ylabel("milliseconds")

    cost = [summaries[mode]["jev_cost_usd"] for mode in MODES]
    bars = axes[2].bar(labels, cost, color=[OPENMED_COLOR, JEV_COLOR])
    axes[2].bar_label(bars, padding=2, fmt="$%.4f")
    axes[2].set_title("Jev cost (OpenMed is self-hosted: $0)")
    axes[2].set_ylabel("USD")
    scale = summaries["with_jev"]["jev_cost_usd"] / NOTES
    axes[2].text(
        1,
        cost[1] * 0.55,
        "\n".join(f"${scale * count:,.2f} per {count:,} notes" for count in COST_SCALE_NOTES),
        ha="center",
        va="top",
        fontsize=9,
        color="#444444",
    )

    fig.suptitle("Time and cost: with Jev vs without Jev")
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


def write_plots(
    summaries: dict[str, dict[str, Any]],
    outcomes: dict[str, list[dict[str, Any]]],
    out_dir: Path,
) -> None:
    plot_time_and_cost(summaries, out_dir / "time_and_cost.png")
    plot_decision_matrices(summaries, out_dir / "decision_matrix.png")
