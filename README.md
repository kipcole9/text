# Text

Text & language processing for Elixir.

A toolkit for tokenization, language identification, sentiment analysis, named-entity recognition, word clouds, phonetic encoding, search ranking, and the supporting plumbing — all in pure BEAM, with optional ML backends behind feature flags.

## Capabilities

### Detection and analysis

* *Language identification* ([`Text.Language.Classifier.Fasttext`](https://hexdocs.pm/text/Text.Language.Classifier.Fasttext.html)) — pure-Elixir port of fastText's `lid.176`, 176 languages, validated bit-for-bit against the reference. ~100 µs per prediction with EXLA.
* *Sentiment analysis* ([`Text.Sentiment`](https://hexdocs.pm/text/Text.Sentiment.html)) — multilingual AFINN lexicons (104 languages + emoji) or XLM-RoBERTa via Bumblebee.
* *Part-of-speech tagging* ([`Text.POS`](https://hexdocs.pm/text/Text.POS.html)) — via Bumblebee, English by default.
* *Named-entity recognition* ([`Text.NER`](https://hexdocs.pm/text/Text.NER.html)) — via Bumblebee, multilingual (10 high-resource languages).
* *Readability* ([`Text.Readability`](https://hexdocs.pm/text/Text.Readability.html)) — Flesch, Flesch-Kincaid, Gunning-Fog, SMOG, ARI, Coleman-Liau, LIX, Dale-Chall, Spache.
* *PII detection and redaction* ([`Text.PII`](https://hexdocs.pm/text/Text.PII.html)) — emails, phones, IBANs, Luhn-validated credit cards, SSNs, IPv4/IPv6, URLs.

### Cleaning and normalization

* *Pipeline cleaning* ([`Text.Clean`](https://hexdocs.pm/text/Text.Clean.html)) — HTML/entity strip, mojibake repair, NFC/NFKC normalization, diacritic folding.
* *Truecasing* ([`Text.Truecase`](https://hexdocs.pm/text/Text.Truecase.html)) — sentence-aware case restoration for ALL-CAPS or lowercased text.
* *Emoji* ([`Text.Emoji`](https://hexdocs.pm/text/Text.Emoji.html)) — detect, count, strip, convert to/from `:short_name:` form, and per-emoji sentiment scoring (Kralj Novak et al. 2015).

### Strings

* *Edit distance* ([`Text.Distance`](https://hexdocs.pm/text/Text.Distance.html)) — Levenshtein, Damerau-Levenshtein, Hamming, Jaro, Jaro-Winkler.
* *N-gram set similarity* ([`Text.Distance`](https://hexdocs.pm/text/Text.Distance.html)) — Jaccard, Sørensen-Dice, Tanimoto, cosine over character n-grams.
* *Set similarity* ([`Text.Similarity`](https://hexdocs.pm/text/Text.Similarity.html)) — Jaccard, Dice, overlap, cosine over arbitrary token sets.
* *Phonetic encoding* — [`Soundex`](https://hexdocs.pm/text/Text.Phonetic.Soundex.html), [`Metaphone`](https://hexdocs.pm/text/Text.Phonetic.Metaphone.html), [`NYSIIS`](https://hexdocs.pm/text/Text.Phonetic.NYSIIS.html), [`Cologne`](https://hexdocs.pm/text/Text.Phonetic.Cologne.html) (German), [`DoubleMetaphone`](https://hexdocs.pm/text/Text.Phonetic.DoubleMetaphone.html), each with `match?/2` for direct equality.
* *Slugification* ([`Text.Slug`](https://hexdocs.pm/text/Text.Slug.html)) — locale-aware Unicode folding with cross-script transliteration.
* *Segmentation* ([`Text.Segment`](https://hexdocs.pm/text/Text.Segment.html)) — UAX #29 word/sentence boundaries with CLDR abbreviation suppressions.
* *Syllable counting* ([`Text.Syllable`](https://hexdocs.pm/text/Text.Syllable.html)) — vowel-group heuristic with an exceptions table.
* *Hyphenation* ([`Text.Hyphenation`](https://hexdocs.pm/text/Text.Hyphenation.html)) — Knuth-Liang patterns; bundled `en-us`, `de-1996`, `fr`, `es`, `it`, `nl`, `pt`, with on-demand fetching for ~80 more from hyph-utf8.

### Spelling and morphology

* *Spell correction* ([`Text.Spell`](https://hexdocs.pm/text/Text.Spell.html)) — Norvig-style edit-distance suggestions backed by `Text.WordFreq`.
* *Lemmatization* ([`Text.Lemma`](https://hexdocs.pm/text/Text.Lemma.html)) — dictionary-driven, ~41k bundled English pairs; ~20 more languages auto-downloadable from michmech via `mix text.download_lemma_data`.
* *Word frequencies* ([`Text.WordFreq`](https://hexdocs.pm/text/Text.WordFreq.html)) — bundled top-30,000 frequencies for `en`, `de`, `fr`, `es`, `it`, `nl`, `pt` with `frequency`, `zipf`, `rank`, `top`.
* *English inflection* ([`Text.Inflect.En`](https://hexdocs.pm/text/Text.Inflect.En.html)) — `pluralize/2` and `singularize/2`, modern and classical modes.

### Statistics and search

* *N-grams and word counts* ([`Text.Ngram`](https://hexdocs.pm/text/Text.Ngram.html), [`Text.Word`](https://hexdocs.pm/text/Text.Word.html)).
* *TF-IDF and BM25* ([`Text.IR`](https://hexdocs.pm/text/Text.IR.html)) — indexed corpus with scoring and top-K search.
* *Collocation extraction* ([`Text.Collocation`](https://hexdocs.pm/text/Text.Collocation.html)) — bigrams ranked by frequency, PMI, or log-likelihood.
* *Concordance* ([`Text.KWIC`](https://hexdocs.pm/text/Text.KWIC.html)) — keyword-in-context lookup.
* *Word embeddings* ([`Text.Embedding`](https://hexdocs.pm/text/Text.Embedding.html)) — load fastText `.vec` files, then cosine similarity, nearest neighbours, and analogies.
* *Word clouds* ([`Text.WordCloud`](https://hexdocs.pm/text/Text.WordCloud.html)) — multilingual keyword extraction (six scoring backends) plus spiral layout and SVG rendering.
* *Extractive summarization* ([`Text.Summarize`](https://hexdocs.pm/text/Text.Summarize.html)) — TextRank and LexRank over Jaccard sentence graphs.
* *Stopwords* ([`Text.Stopwords`](https://hexdocs.pm/text/Text.Stopwords.html)) — bundled lists for ~60 languages from [stopwords-iso](https://github.com/stopwords-iso/stopwords-iso).

## Installation

```elixir
def deps do
  [
    {:text, "~> 0.5.0"}
  ]
end
```

For the language identifier, fetch the `lid.176.bin` model once after install:

```sh
mix text.download_lid176
```

For production environments using the optional Bumblebee-backed modules, `mix text.download_models` (plural) pre-fetches every external artefact — `lid.176.bin` plus the default Hugging Face checkpoints — so the first call to each module never hits the network.

## A taste

```elixir
# Sentiment — multilingual, no model download by default.
Text.Sentiment.analyze("J'adore ce livre.", language: :fr).label
#=> :positive

# Language identification — load the fastText model once.
{:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load(
  Path.join(:code.priv_dir(:text), "lid_176/lid.176.bin")
)

{:ok, "es"} = Text.Language.Classifier.Fasttext.classify("Hola, ¿cómo estás?", model)

# Word cloud → SVG file in four piped steps.
text
|> Text.WordCloud.terms(language: :en)
|> Text.WordCloud.Layout.layout(width: 800, height: 600, rotations: :radial)
|> Text.WordCloud.SVG.render(palette: Color.Palette.tonal("#3b82f6"))
|> then(&File.write!("cloud.svg", &1))
```

## Guides

In-depth walkthroughs with worked examples:

* *[Text classification (language identification)](https://hexdocs.pm/text/text_classification.html)* — setup, `detect/3`, CLDR locale resolution, Hans/Hant disambiguation, performance tuning.

* *[Sentiment analysis](https://hexdocs.pm/text/sentiment.html)* — lexicon vs Bumblebee backends, multilingual lexicons, custom lexicons, threshold tuning, production wiring.

* *[Part-of-speech tagging and NER](https://hexdocs.pm/text/pos_ner.html)* — Bumblebee setup, tag sets, model pre-download, named `Nx.Serving`s for high-QPS workloads.

* *[Keyword-in-context concordance](https://hexdocs.pm/text/kwic.html)* — `Text.KWIC.concordance/3`, formatting, collocate scans, sense disambiguation patterns.

* *[Word clouds](https://hexdocs.pm/text/word_clouds.html)* — six scoring backends (YAKE!, frequency, RAKE, TextRank, TF-IDF, KeyBERT), Wordle-style layouts (`:radial`/`:spiral`), SVG rendering with `Color.Palette` integration.

## Optional dependencies

The package works without any optional deps. Adding them enables progressively heavier capabilities:

| Dep | Enables |
|---|---|
| [`:exla`](https://hex.pm/packages/exla) | Order-of-magnitude faster inference for Fasttext and the Bumblebee-backed modules. Strongly recommended in production. |
| [`:bumblebee`](https://hex.pm/packages/bumblebee) | Neural sentiment, POS, NER, and the KeyBERT word-cloud backend. |
| [`:localize`](https://hex.pm/packages/localize) | CLDR-canonical locale resolution (`fr-Latn-CA`, `zh-Hans-CN`) and `Localize.LanguageTag` input shapes. |
| [`:color`](https://hex.pm/packages/color) | `Color.Palette.Tonal` and `Theme` palettes for SVG word-cloud rendering. |
| `:text_stemmer` | Snowball stemming (~30 languages) for word-cloud morphological-variant consolidation. |

Calls that need a missing optional dep raise with installation instructions; the rest of the package keeps working.

Every public function that takes a `:language` (or `:locale`) accepts an atom (`:fr`), a string (`"fr"`, `"fr-CA"`, `"zh-Hans-CN"`), or a `Localize.LanguageTag` struct (when `:localize` is loaded). See [`Text.Language`](https://hexdocs.pm/text/Text.Language.html) for the normalisation helpers.

## Roadmap

* *Quantized model support* for `lid.176.ftz` (917 KB variant).
* *`Nx.Serving` for batched inference* for throughput-bound workloads.
* *CLDR-tailored segmentation* once the [`unicode_set`](https://github.com/elixir-unicode/unicode_set) regex engine matures.

## License

Apache 2.0 — see [LICENSE.md](https://github.com/kipcole9/text/blob/v0.3.0/LICENSE.md).
