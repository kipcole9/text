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

## Active follow-up — bundled-data extensions

Improvements to the modules above that don't change their public API.

* **`Text.Readability.dale_chall/2` and `Text.Readability.spache/2`** — bundle the Dale-Chall easy-words list (~3,000 words) and the Spache list (~1,000 words) so the two remaining classic indices ship.
* **`Text.Hyphenation` language packs** — bundle `hyph-de`, `hyph-fr`, `hyph-es`, `hyph-it`, `hyph-pt`, `hyph-nl` patterns alongside `en-us`.
* **`Text.Lemma` language packs** — bundle the other top-tier `lemmatization-lists` languages (de, fr, es, it, nl, pt).
* **`Text.WordFreq` language packs** — bundle frequency tables for the same set, sourced from the `wordfreq` upstream.
* **`Text.Emoji.sentiment/1`** — bundle the Kralj Novak et al. (2015) emoji sentiment ranking and expose a per-emoji score.
* **`unicode_emoji` package** — extract a standalone hex package (mirroring `unicode_string`, `unicode_set`) that ships the full CLDR emoji annotations: short names, keywords, presentation/component flags, ZWJ sequence definitions, and skin-tone modifier handling. Once published, `Text.Emoji` drops its hand-curated in-module lookup and sources every name from `unicode_emoji`, gaining full coverage of the emoji repertoire and proper handling of ZWJ sequences (e.g. `👨‍👩‍👧‍👦` as one entity rather than four pictographs).
* **`Text.Summarize` similarity backends** — option to use TF-IDF cosine instead of Jaccard, and (when `Text.Embedding` is loaded) static-embedding cosine.

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
