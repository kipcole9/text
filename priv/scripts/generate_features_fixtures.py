#!/usr/bin/env python3
"""
Generate golden feature-vector fixtures for differential testing of the
pure-Elixir port of `Dictionary::getStringNoNewline` /
`Dictionary::addSubwords`.

For each line in a curated list, this script tokenizes the input on the
same byte set fastText uses, runs each token through
`model.get_subwords/1` against `lid.176.bin`, drops tokens shaped like
labels, and concatenates the per-token indices into the flat feature
vector that the C++ would average at inference.

Note that this re-derives the feature path *from outside* the C++
library because the official Python API does not expose
`Dictionary::getLine` / `getStringNoNewline` directly. The pieces it
does expose (`get_subwords`, `get_word_id`, the args block) are enough
to reconstruct what the C++ would produce — and those pieces are
themselves what the Phase 3 test suite already validates against the
reference.

Requirements:
  * Python 3.8+
  * `pip install fasttext`
  * `priv/lid_176/lid.176.bin` present.

Usage:
  python3 priv/scripts/generate_features_fixtures.py
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


# fastText's `Dictionary::readWord` whitespace set.
WHITESPACE = {ord(" "), ord("\n"), ord("\r"), ord("\t"), ord("\v"), ord("\f"), 0}
LABEL_PREFIX = "__label__"


# A spread of natural-language inputs. Includes mixed scripts, OOV-heavy
# tokens, leading/trailing whitespace, and empty fragments to exercise
# the tokenizer edge cases.
CURATED_INPUTS = [
    "hello world",
    "the quick brown fox jumps over the lazy dog",
    "  hello\tworld\n",  # weird whitespace
    "Bonjour le monde",
    "Hola, ¿cómo estás?",
    "你好世界",
    "日本語はとても面白い",
    "Привет, мир!",
    "γεια σας κόσμε",
    "مرحبا بالعالم",
    "नमस्ते दुनिया",
    "안녕하세요 세계",
    "मेरा भारत महान",
    "supercalifragilisticexpialidocious is a long word",
    "qzxqzxqzx oovword anothertoken",
    "ABC123 mixedCase TestToken",
    "__label__en should be dropped from features",
    "leading and trailing   ",
    "",  # empty
    "    ",  # whitespace only
    "single",
    "naïve café résumé",
    "العربية والعبرية والروسية",
]


def tokenize(text: str) -> list[str]:
    """Re-implement fastText's whitespace tokenizer in pure Python."""
    encoded = text.encode("utf-8")
    tokens: list[bytes] = []
    start = 0
    for i, b in enumerate(encoded):
        if b in WHITESPACE:
            if i > start:
                tokens.append(encoded[start:i])
            start = i + 1
    if len(encoded) > start:
        tokens.append(encoded[start:])
    return [t.decode("utf-8") for t in tokens]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, default=Path("priv/lid_176/lid.176.bin"))
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("test/fixtures/golden_features.json"),
    )
    args = parser.parse_args()

    if not args.model.is_file():
        print(f"error: model not found at {args.model}", file=sys.stderr)
        return 1

    try:
        import fasttext  # type: ignore
    except ImportError:
        print("error: install with `pip install fasttext`", file=sys.stderr)
        return 1

    print(f"Loading {args.model}...", file=sys.stderr)
    model = fasttext.load_model(str(args.model))
    nwords = len(model.get_words())
    nlabels = len(model.get_labels())

    entries = []
    for text in CURATED_INPUTS:
        tokens = tokenize(text)
        feature_indices: list[int] = []
        per_token: list[dict] = []
        for token in tokens:
            wid = model.get_word_id(token)
            in_vocab = wid >= 0
            if in_vocab and wid >= nwords:
                # Known label entry — drop.
                kind = "label"
                token_indices: list[int] = []
            elif (not in_vocab) and token.startswith(LABEL_PREFIX):
                # Unknown but label-shaped — drop.
                kind = "label_oov"
                token_indices = []
            else:
                # Word-typed: subwords (and the wid itself when present).
                _subwords, indices = model.get_subwords(token)
                token_indices = [int(i) for i in indices]
                kind = "word" if in_vocab else "word_oov"
            feature_indices.extend(token_indices)
            per_token.append({"token": token, "kind": kind, "indices": token_indices})

        entries.append({
            "text": text,
            "tokens": tokens,
            "per_token": per_token,
            "features": feature_indices,
        })

    output = {
        "model": str(args.model),
        "nwords": nwords,
        "nlabels": nlabels,
        "fasttext_version": getattr(fasttext, "__version__", "unknown"),
        "entries": entries,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as fp:
        json.dump(output, fp, ensure_ascii=False, indent=2)
        fp.write("\n")

    print(f"Wrote {len(entries)} entries to {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
