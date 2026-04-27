#!/usr/bin/env python3
"""
Generate golden top-k prediction fixtures for differential testing of the
pure-Elixir port of fastText's hierarchical-softmax inference path.

For each line in a curated input set, runs `model.predict(text, k=K)`
against `lid.176.bin` and records the returned (label, probability)
pairs. The Elixir test suite calls
`Text.Language.Classifier.Fasttext.Inference.predict/3` on the same
inputs and asserts label-set parity plus probability agreement within a
small tolerance.

Requirements:
  * Python 3.8+
  * `pip install fasttext`
  * `priv/lid_176/lid.176.bin` present.

Usage:
  python3 priv/scripts/generate_predict_fixtures.py [--top-k N]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


CURATED_INPUTS = [
    "Hello world. This is an English sentence used for language identification testing.",
    "Bonjour le monde. Ceci est une phrase française utilisée pour tester l'identification de la langue.",
    "Hola mundo. Esta es una frase en español para probar la identificación del idioma.",
    "Hallo Welt. Dies ist ein deutscher Satz zur Sprachidentifizierung.",
    "Ciao mondo. Questa è una frase italiana per testare il riconoscimento della lingua.",
    "Olá mundo. Esta é uma frase em português para testar a identificação do idioma.",
    "Hej världen. Detta är en svensk mening för språkidentifiering.",
    "Hallo wereld. Dit is een Nederlandse zin voor taalidentificatie.",
    "Witaj świecie. To jest polskie zdanie do identyfikacji języka.",
    "Привет мир. Это русское предложение для определения языка.",
    "Γεια σου κόσμε. Αυτή είναι μια ελληνική πρόταση για την αναγνώριση γλώσσας.",
    "你好世界。这是一个用于语言识别的中文句子。",
    "こんにちは世界。これは言語識別のための日本語の文です。",
    "안녕하세요 세계. 이것은 언어 식별을 위한 한국어 문장입니다.",
    "مرحبا بالعالم. هذه جملة عربية لاختبار التعرف على اللغة.",
    "שלום עולם. זה משפט בעברית לזיהוי שפה.",
    "สวัสดีชาวโลก นี่คือประโยคภาษาไทยสำหรับการระบุภาษา",
    "Xin chào thế giới. Đây là một câu tiếng Việt để nhận dạng ngôn ngữ.",
    "Merhaba dünya. Bu, dil tanıma için bir Türkçe cümledir.",
    "Hei maailma. Tämä on suomenkielinen lause kielentunnistusta varten.",
    "नमस्ते दुनिया। यह भाषा पहचान के लिए एक हिंदी वाक्य है।",
    "வணக்கம் உலகம். இது மொழி அடையாளத்திற்கான ஒரு தமிழ் வாக்கியம்.",
    # Short and ambiguous inputs.
    "Hello world",
    "Bonjour",
    "Hola",
    "Привет",
    "你好",
    "the cat sat on the mat",
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, default=Path("priv/lid_176/lid.176.bin"))
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("test/fixtures/golden_predictions.json"),
    )
    parser.add_argument("--top-k", type=int, default=5)
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

    entries = []
    for text in CURATED_INPUTS:
        # The Python wrapper replaces newlines with spaces before
        # tokenization. We mirror that here.
        normalised = text.replace("\n", " ")
        labels, probs = model.predict(normalised, k=args.top_k)
        entries.append({
            "text": text,
            "predictions": [
                {"label": label.removeprefix("__label__"), "probability": float(prob)}
                for label, prob in zip(labels, probs)
            ],
        })

    output = {
        "model": str(args.model),
        "fasttext_version": getattr(fasttext, "__version__", "unknown"),
        "top_k": args.top_k,
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
