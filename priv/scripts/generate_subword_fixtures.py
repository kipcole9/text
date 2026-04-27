#!/usr/bin/env python3
"""
Generate golden subword fixtures for differential testing of the
pure-Elixir port of `Dictionary::computeSubwords` / `Dictionary::pushHash`.

For each word in a curated list, this script asks the official fastText
library running against `lid.176.bin` for:

  * the list of subword strings the word generates,
  * the list of input-matrix row indices those subwords map to.

The Elixir test suite then re-derives both lists from
`Text.Language.Classifier.Fasttext.Subwords` and asserts equality.

Requirements:
  * Python 3.8+
  * `pip install fasttext`
  * `priv/lid_176/lid.176.bin` present.

Usage:
  python3 priv/scripts/generate_subword_fixtures.py \
    [--model PATH] [--output PATH] [--extra-words FILE]

The script must be run from the repository root.

The resulting fixture file pairs each word with `subwords` (strings) and
`indices` (ints). For words that are themselves in the lid.176 vocabulary,
the first entry of each list corresponds to the word itself and the rest
are character n-gram subwords; the Elixir tests inspect both halves.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


CURATED_WORDS = [
    # ASCII words at the easy end of the difficulty curve.
    "the", "and", "of", "a", "to", "in", "is", "it", "for", "on",
    "language", "fasttext", "elixir", "embedding", "subword",
    # Short/edge cases.
    "x", "ab", "abc", "abcd", "abcde",
    # Latin with diacritics.
    "café", "naïve", "über", "résumé", "façade", "mañana",
    "été", "Zürich", "Łódź", "São",
    # Cyrillic.
    "привет", "мир", "русский", "язык", "москва",
    # Greek.
    "γεια", "κόσμε", "ελληνικά",
    # Arabic.
    "مرحبا", "العربية", "بالعالم",
    # Hebrew.
    "שלום", "עברית",
    # Devanagari.
    "नमस्ते", "हिंदी", "दुनिया",
    # CJK (Chinese, Japanese, Korean).
    "你好", "世界", "中文", "汉字",
    "日本語", "東京", "こんにちは",
    "안녕하세요", "한국어",
    # Tamil & Thai.
    "தமிழ்", "வணக்கம்",
    "สวัสดี", "ภาษา",
    # Mixed-script and tricky byte boundaries.
    "ABC123", "test_word", "naïve-café",
    # Long-ish strings to exercise n-gram counts.
    "supercalifragilisticexpialidocious",
    "antidisestablishmentarianism",
    # Made-up tokens unlikely to be in the vocab — exercises the
    # subwords-only path.
    "qzxqzxqzx", "elixirtest42", "wzx日本ABC",
]


def read_extra(path: Path) -> list[str]:
    extra: list[str] = []
    with path.open("r", encoding="utf-8") as fp:
        for raw in fp:
            line = raw.strip()
            if line and not line.startswith("#"):
                extra.append(line)
    return extra


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, default=Path("priv/lid_176/lid.176.bin"))
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("test/fixtures/golden_subwords.json"),
    )
    parser.add_argument("--extra-words", type=Path, default=None)
    args = parser.parse_args()

    if not args.model.is_file():
        print(f"error: model not found at {args.model}", file=sys.stderr)
        return 1

    try:
        import fasttext  # type: ignore
    except ImportError:
        print(
            "error: install with `pip install fasttext`",
            file=sys.stderr,
        )
        return 1

    print(f"Loading {args.model}...", file=sys.stderr)
    model = fasttext.load_model(str(args.model))

    nwords = len(model.get_words())
    nlabels = len(model.get_labels())
    fargs = model.f.getArgs()
    minn = fargs.minn
    maxn = fargs.maxn
    bucket = fargs.bucket

    words = list(CURATED_WORDS)
    if args.extra_words is not None and args.extra_words.is_file():
        words.extend(read_extra(args.extra_words))

    # De-duplicate while preserving order.
    seen: set[str] = set()
    unique_words: list[str] = []
    for w in words:
        if w not in seen:
            seen.add(w)
            unique_words.append(w)

    entries = []
    for word in unique_words:
        subwords, indices = model.get_subwords(word)
        entries.append({
            "word": word,
            "in_vocab": model.get_word_id(word) >= 0,
            "subwords": list(subwords),
            "indices": [int(i) for i in indices],
        })

    output = {
        "model": str(args.model),
        "fasttext_version": getattr(fasttext, "__version__", "unknown"),
        "nwords": nwords,
        "nlabels": nlabels,
        "minn": minn,
        "maxn": maxn,
        "bucket": bucket,
        "entries": entries,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as fp:
        json.dump(output, fp, ensure_ascii=False, indent=2)
        fp.write("\n")

    print(
        f"Wrote {len(entries)} entries to {args.output}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
