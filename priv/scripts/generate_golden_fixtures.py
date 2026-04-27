#!/usr/bin/env python3
"""
Generate golden prediction fixtures for the pure-Elixir lid.176 port.

Reads test inputs from `test/fixtures/test_strings.json`, runs each through
the official fastText library against the canonical `lid.176.bin` model,
and writes per-input top-K predictions to
`test/fixtures/golden_predictions.json`.

The Elixir implementation is then validated against this output as ground
truth (see Phase 8 of the implementation plan).

Requirements:
  * Python 3.8+
  * `pip install fasttext` (the official Facebook Research package)
  * `priv/lid_176/lid.176.bin` present (run `mix text.download_model`).

Usage:
  python3 priv/scripts/generate_golden_fixtures.py [--top-k N]

The script must be run from the repository root.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument(
        "--top-k",
        type=int,
        default=5,
        help="Number of label predictions to record per input (default: 5).",
    )
    parser.add_argument(
        "--model",
        type=Path,
        default=Path("priv/lid_176/lid.176.bin"),
        help="Path to the fastText model file (default: priv/lid_176/lid.176.bin).",
    )
    parser.add_argument(
        "--inputs",
        type=Path,
        default=Path("test/fixtures/test_strings.json"),
        help="Path to the canonical test input file.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("test/fixtures/golden_predictions.json"),
        help="Where to write the golden fixture file.",
    )
    args = parser.parse_args()

    if not args.model.is_file():
        print(
            f"error: model not found at {args.model}. "
            "Run 'mix text.download_model' first.",
            file=sys.stderr,
        )
        return 1

    if not args.inputs.is_file():
        print(f"error: inputs file not found at {args.inputs}.", file=sys.stderr)
        return 1

    try:
        import fasttext  # type: ignore
    except ImportError:
        print(
            "error: the 'fasttext' Python package is not installed.\n"
            "Install with: pip install fasttext",
            file=sys.stderr,
        )
        return 1

    with args.inputs.open("r", encoding="utf-8") as fp:
        spec = json.load(fp)

    print(f"Loading {args.model}...", file=sys.stderr)
    model = fasttext.load_model(str(args.model))

    predictions = []
    for entry in spec["strings"]:
        text = entry["text"]
        labels, probs = model.predict(text.replace("\n", " "), k=args.top_k)
        predictions.append({
            "text": text,
            "expected_label": entry.get("expected_label"),
            "predictions": [
                {
                    # Strip the __label__ prefix so the fixture is directly
                    # comparable with the Elixir parser's `model.labels`.
                    "label": label.removeprefix("__label__"),
                    "probability": float(prob),
                }
                for label, prob in zip(labels, probs)
            ],
        })

    output = {
        "generator": "fasttext",
        "model": str(args.model),
        "top_k": args.top_k,
        "fasttext_version": getattr(fasttext, "__version__", "unknown"),
        "predictions": predictions,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as fp:
        json.dump(output, fp, ensure_ascii=False, indent=2)
        fp.write("\n")

    print(
        f"Wrote {len(predictions)} predictions to {args.output}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
