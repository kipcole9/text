#!/usr/bin/env python3
"""
Reference-side measurements for the comparative performance report.

Loads `lid.176.bin` via the official `fasttext` Python bindings and
collects load time, resident-memory delta, per-prediction wall time
on the same input set the Elixir companion script uses, plus the
sentence-vector and predict timings broken down separately.

Output goes to stdout in the same format as the Elixir script so the
two reports can be diffed.

Run with:

    /usr/bin/python3 priv/scripts/comparative_perf_report.py

(Use the same Python interpreter that has `fasttext` installed — the
prebuilt wheel lives in `/Users/kip/Library/Python/3.9` here.)
"""

from __future__ import annotations

import json
import os
import resource
import sys
import time
from pathlib import Path
from statistics import median


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
MODEL_PATH = REPO_ROOT / "priv" / "lid_176" / "lid.176.bin"
INPUTS_PATH = REPO_ROOT / "test" / "fixtures" / "test_strings.json"
PREDICTIONS_PATH = REPO_ROOT / "test" / "fixtures" / "golden_predictions.json"

BENCH_INPUTS = {
    "short ASCII (3 words)": "the cat sat",
    "medium ASCII (10 words)":
        "the quick brown fox jumps over the lazy dog now",
    "long sentence (~80 chars)":
        "Hello world. This is an English sentence used for language identification testing.",
    "Cyrillic": "Это русское предложение для определения языка.",
    "CJK (Chinese)": "这是一个用于语言识别的中文句子。",
    "CJK (Japanese)": "これは言語識別のための日本語の文です。",
}


def rss_mb() -> float:
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    # Linux returns KiB; macOS returns bytes. Treat anything > 10 MiB as
    # bytes (heuristic — well above any conceivable Python startup RSS).
    if sys.platform == "darwin":
        return rss / 1024 / 1024
    return rss / 1024  # KiB to MiB


def main() -> int:
    if not MODEL_PATH.is_file():
        print(f"error: model not found at {MODEL_PATH}", file=sys.stderr)
        return 1

    try:
        import fasttext  # type: ignore
    except ImportError:
        print("error: install with `pip install fasttext`", file=sys.stderr)
        return 1

    rss_before = rss_mb()
    print("\n=== Loading model ===")
    t0 = time.perf_counter()
    model = fasttext.load_model(str(MODEL_PATH))
    load_ms = (time.perf_counter() - t0) * 1000
    rss_after = rss_mb()

    print(f"Load time: {load_ms:.1f} ms")
    print(f"Resident model memory: {rss_after - rss_before:.1f} MB (RSS delta)")
    print(f"nwords={len(model.get_words())} nlabels={len(model.get_labels())}")

    # Accuracy
    print("\n=== Accuracy on curated test inputs ===")
    with INPUTS_PATH.open(encoding="utf-8") as fp:
        spec = json.load(fp)

    correct = 0
    confidences = []
    for entry in spec["strings"]:
        text = entry["text"]
        expected = entry["expected_label"]
        labels, probs = model.predict(text.replace("\n", " "), k=1)
        predicted = labels[0].removeprefix("__label__")
        confidences.append(float(probs[0]))
        if predicted.split("-")[0] == expected:
            correct += 1

    total = len(spec["strings"])
    mean_conf = sum(confidences) / len(confidences) if confidences else 0.0
    print(f"Top-1 accuracy: {correct}/{total} ({correct / total * 100:.1f}%)")
    print(f"Mean top-1 confidence: {mean_conf:.3f}")

    # Speed
    print("\n=== Speed (per prediction, warm) ===")
    print(f"{'input':<40} {'median (μs)':>13} {'p99 (μs)':>10}")
    print("-" * 40 + " " + "-" * 13 + " " + "-" * 10)

    warmup = 50
    measure = 200

    speed_results = {}
    for label, text in BENCH_INPUTS.items():
        normalised = text.replace("\n", " ")
        for _ in range(warmup):
            model.predict(normalised, k=1)

        samples_us = []
        for _ in range(measure):
            t0 = time.perf_counter()
            model.predict(normalised, k=1)
            samples_us.append((time.perf_counter() - t0) * 1_000_000)

        samples_us.sort()
        median_us = samples_us[measure // 2]
        p99_us = samples_us[measure * 99 // 100]
        speed_results[label] = (median_us, p99_us)
        print(f"{label:<40} {median_us:>13.0f} {p99_us:>10.0f}")

    # Memory per prediction is harder to measure precisely in CPython
    # (no analogue of :erlang.memory). Skip and report N/A.

    print("\n=== Memory per prediction ===")
    print("Not directly comparable to the Erlang report — reported as N/A.")

    print("\n=== Done ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
