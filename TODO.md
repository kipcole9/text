# TODO

Roadmap for closing the gap with the Python (NLTK / spaCy / TextBlob / gensim / textstat) and Ruby (treat / pragmatic_segmenter / ruby-spacy) general-purpose NLP toolkits.

## Done — Pure-BEAM additions (2026-04-29)

All 11 land in this batch. Each is implemented, doctested, unit-tested, and passes `mix compile --warnings-as-errors`, `mix test`, `mix dialyzer`, and `MIX_ENV=release mix docs`.

* **`Text.Syllable`** — vowel-group heuristic English syllable counter with a small exceptions table. Suitable for readability metrics; defer to `Text.Hyphenation` for typographic accuracy.
* **`Text.Readability`** — Flesch, Flesch-Kincaid, Gunning-Fog, SMOG, ARI, Coleman-Liau, LIX. Plus `statistics/2` and a one-pass `metrics/2`.
* **`Text.Hyphenation`** — Liang's algorithm with bundled `hyph-en-us` patterns (~5,000 patterns + DEK exception list, permissive Knuth licence). `hyphenate/2`, `points/2`, `count/2`, `load_language/3`.
* **`Text.WordFreq`** — bundled top-30,000 American English word frequencies (Norvig / Google Web Trillion Corpus). `count`, `frequency`, `zipf`, `rank`, `top`, `vocabulary_size`, `load_language/2`.
* **`Text.Spell`** — Norvig-style edit-distance spell correction over `Text.WordFreq`. `correct/2`, `candidates/2`, `known?/2`, `edits1/1`. Distance-1 and distance-2 edits.
* **`Text.Lemma`** — dictionary-driven lemmatization with bundled English data (Měchura `lemmatization-lists`, ~41k pairs, ODL). `lemmatize/2`, `lemmatize_text/2`, `known?/2`, `load_language/2`.
* **`Text.Truecase`** — sentence-aware case restoration with a curated lexicon of proper nouns, acronyms, and brand names. `truecase/2`, `add_terms/1`.
* **`Text.Clean`** — HTML/XML strip with entity decoding (named + numeric), whitespace collapse, control-char stripping, Unicode normalization (NFC/NFD/NFKC/NFKD), `ftfy`-style mojibake repair, and a chained `clean/2` pipeline.
* **`Text.Emoji`** — `Extended_Pictographic`-based detection plus a curated short-name lookup. `extract`, `count`, `contains?`, `strip`, `demojize/2`, `emojize/2`, `add_emoji/1`.
* **`Text.PII`** — pattern-based detection and redaction for emails, phones, IBANs, credit cards (Luhn-validated), SSNs, IPv4, IPv6, and URLs. `detect/2`, `redact/2`, `types/0`.
* **`Text.Summarize`** — extractive summarization via TextRank and LexRank with Jaccard-similarity sentence graphs. `summarize/2`, `summarize_sentences/2`, `scores/2`.

## Done — bundled-data extensions (2026-05-02, in 0.5.0)

* **Dale-Chall + Spache** — bundled `priv/readability/dale_chall.txt` (2,949 words) and `priv/readability/spache.txt` (1,063 words) from the MIT-licensed `py-readability-metrics` distribution. `Text.Readability.dale_chall/2` and `spache/2` shipped; `statistics/2` now also returns `:difficult_words` and `:unfamiliar_words`.

* **Hyphenation language packs** — bundled `de-1996`, `fr`, `es`, `it`, `nl`, `pt` `.tex` pattern files from hyph-utf8 (each under its upstream MIT/X11/BSD/LPPL license, headers preserved). All compile-time, zero-I/O.

* **WordFreq language packs** — bundled top-30,000 entries each for `de`, `fr`, `es`, `it`, `nl`, `pt` from Hermit Dave's MIT-licensed FrequencyWords (OpenSubtitles 2018 corpus). Compile-time, zero-I/O.

* **Emoji Sentiment Ranking** — bundled v1.0 (Kralj Novak et al., 2015, CC-BY-SA 3.0) at `priv/emoji_sentiment/`. `Text.Emoji.sentiment/1` and `text_sentiment/1` shipped.

* **Lemma packs deferred** — non-English `lemmatization-lists` files were evaluated but not bundled; the smallest (French, 4.7 MB raw) by itself would push the package near hex's 8 MB limit. Mitigation: added `mix text.download_lemma_data <lang>` to fetch from upstream into the `Text.Data` cache without requiring the per-app `auto_download_lemma_data` flag, and the `Text.Lemma` moduledoc now enumerates the ~20 upstream-available languages and notes the absence of any Dutch (`nl`) dictionary upstream.

## Active follow-up

* **`unicode_emoji` package** — extract a standalone hex package (mirroring `unicode_string`, `unicode_set`) that ships the full CLDR emoji annotations: short names, keywords, presentation/component flags, ZWJ sequence definitions, and skin-tone modifier handling. Once published, `Text.Emoji` drops its hand-curated in-module lookup and sources every name from `unicode_emoji`, gaining full coverage of the emoji repertoire and proper handling of ZWJ sequences (e.g. `👨‍👩‍👧‍👦` as one entity rather than four pictographs).

* **`Text.Summarize` similarity backends** — option to use TF-IDF cosine instead of Jaccard, and (when `Text.Embedding` is loaded) static-embedding cosine.

* **Lemma data as separate hex packages** — long-term answer to the lemma-bundling size problem: per-language `:text_lemma_<lang>` companion packages so apps depend only on the languages they need.

## Deferred — Optional ML extensions (Bumblebee feature flag)

Mirror the existing pattern from `Text.Sentiment`, `Text.POS`, `Text.NER`: pure code with the heavy lifting behind `:bumblebee`.

* **`Text.Embedding.Sentence`** — sentence-transformers checkpoints via Bumblebee. Contextual counterpart to the existing static fastText `Text.Embedding`.
* **`Text.Classify.ZeroShot`** — BART-MNLI / DeBERTa-MNLI zero-shot classification.
* **`Text.Translate`** — NLLB-200 or MarianMT.
* **`Text.QA`** — span-extraction QA (BERT-style) via Bumblebee.
* **`Text.Toxicity`** / **`Text.Emotion`** — fine-tuned classifier wrappers, same shape as `Text.Sentiment`'s neural backend.
* **`Text.Summarize.abstractive/2`** — abstractive summarization via a Bumblebee seq2seq model (BART, T5, Pegasus).

## Deferred — Heavy / stretch

Likely to dominate the project; revisit only if there's clear demand.

* Dependency parsing (spaCy / Stanza territory).
* Coreference resolution.
* Constituency parsing.
* Topic modelling (LDA / NMF) — largely superseded by embeddings + clustering for most use cases.
* Text augmentation (`nlpaug`-style).
