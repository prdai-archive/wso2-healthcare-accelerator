import json
import os
import statistics
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest

from test_policy import load_policy_module


@dataclass(frozen=True)
class Candidate:
    name: str
    model_id: str
    reported_f1: float
    parameters_millions: int
    artifact_mb: float
    source_url: str


CANDIDATES = (
    Candidate(
        "ClinicalE5-Small",
        "OpenMed/OpenMed-PII-ClinicalE5-Small-33M-v1",
        0.9306,
        33,
        69.6,
        "https://huggingface.co/OpenMed/OpenMed-PII-ClinicalE5-Small-33M-v1",
    ),
    Candidate(
        "LiteClinical-Small",
        "OpenMed/OpenMed-PII-LiteClinical-Small-66M-v1",
        0.9485,
        66,
        138.0,
        "https://huggingface.co/OpenMed/OpenMed-PII-LiteClinical-Small-66M-v1",
    ),
    Candidate(
        "SuperClinical-Small",
        "OpenMed/OpenMed-PII-SuperClinical-Small-44M-v1",
        0.9539,
        44,
        467.0,
        "https://huggingface.co/OpenMed/OpenMed-PII-SuperClinical-Small-44M-v1",
    ),
    Candidate(
        "SuperMedical-Base",
        "OpenMed/OpenMed-PII-SuperMedical-Base-125M-v1",
        0.9557,
        125,
        0.0,
        "https://huggingface.co/OpenMed/OpenMed-PII-SuperMedical-Base-125M-v1",
    ),
)


def _sample_bundles() -> list[tuple[str, str, int]]:
    root = Path(
        os.getenv(
            "SYNTHEA_FHIR_DIR",
            Path(__file__).parents[6] / "wso2-solutions-healthcare/iac/build/synthea-data/fhir",
        )
    )
    files = sorted(root.glob("*.json"))
    if not files:
        pytest.skip(f"No Synthea FHIR JSON found under {root}")

    resources = [json.loads(path.read_text()) for path in files[:10]]
    max_text_bytes = int(os.getenv("MODEL_COMPARISON_MAX_TEXT_BYTES", "16384"))
    bundles = []
    for count in (1, 5, 10):
        bundle = {"resourceType": "Bundle", "type": "batch", "entry": [{"resource": item} for item in resources[:count]]}
        serialized = json.dumps(bundle)
        bundles.append((f"{count}-resource", serialized[:max_text_bytes], len(serialized.encode())))
    return bundles


def _plot(results: list[dict[str, Any]], output: Path) -> None:
    import matplotlib.pyplot as plt

    names = [item["name"] for item in results]
    f1 = [item["reported_f1"] for item in results]
    latency = [item["average_seconds"] for item in results]
    figure, axes = plt.subplots(1, 2, figsize=(12, 5))
    axes[0].scatter(latency, f1, s=80, color="#2f6f9f")
    for item in results:
        axes[0].annotate(item["name"], (item["average_seconds"], item["reported_f1"]), xytext=(6, 6), textcoords="offset points")
    axes[0].set_title("Quality versus average policy latency")
    axes[0].set_xlabel("Average redaction time (seconds)")
    axes[0].set_ylabel("Reported Nemotron-PII micro-F1")
    axes[0].set_ylim(min(f1) - 0.005, max(f1) + 0.005)
    axes[0].grid(alpha=0.25)
    axes[1].bar(names, latency, color="#c26d3a")
    axes[1].set_title("Average policy redaction time")
    axes[1].set_ylabel("seconds per bundle")
    axes[1].tick_params(axis="x", rotation=30)
    figure.tight_layout()
    figure.savefig(output, dpi=160)
    plt.close(figure)


@pytest.mark.model_comparison
def test_policy_model_comparison(tmp_path: Path, capsys) -> None:
    if os.getenv("RUN_MODEL_COMPARISON") != "1":
        pytest.skip("set RUN_MODEL_COMPARISON=1 to download and run all candidate models")

    policy_module = load_policy_module()
    results = []
    for candidate in CANDIDATES:
        policy = policy_module.PiiMaskingPolicy(model_name=candidate.model_id)
        load_started = time.perf_counter()
        policy._redact_text("Patient Jane Doe, DOB 1985-03-15", {})
        load_seconds = time.perf_counter() - load_started
        timings = []
        for _, bundle, _ in _sample_bundles():
            mapping: dict[str, str] = {}
            started = time.perf_counter()
            policy._redact_text(bundle, mapping)
            timings.append(time.perf_counter() - started)
        result = {
            "name": candidate.name,
            "model_id": candidate.model_id,
            "reported_f1": candidate.reported_f1,
            "load_seconds": load_seconds,
            "average_seconds": statistics.mean(timings),
            "median_seconds": statistics.median(timings),
            "bundle_seconds": timings,
        }
        results.append(result)
        print(json.dumps(result))

    output = Path(os.getenv("MODEL_COMPARISON_PLOT", str(tmp_path / "model-comparison.png")))
    _plot(results, output)
    print(json.dumps({"plot": str(output), "models": len(results)}))
