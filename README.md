# Text

Text & language processing for Elixir.  Initial release focuses on:

* [x] n-gram generation from text
* [x] pluralization of english words
* [x] word counting (word frequencies)
* [x] language detection using pluggable classifier, vocabulary and corpus backends.

Second phase will focus on:

* Stemming
* tokenization and part-of-speech tagging (at least for english)
* Sentiment analysis

Each of these phases requires prior development. See [below](#down_the_rabbit_hole).

## Status Update Sept 2021

The `Text` project remains active and maintained. However with the advent of the amazing [Numerical Elixir (Nx)](https://github.com/elixir-nx) project, many improved opportunities to leverage ML for text analysis open up and this is the planned path.  I expect to focus using ML for the additional planned functionality as a calendar year 2022 project.  Bug reports, PR and suggests are welcome!

## Installation

```elixir
def deps do
  [
    {:text, "~> 0.2.0"}
  ]
end
```

## Word Counting

`text` contains an implementation of word counting that is oriented towards large streams of words rather than discrete strings. Input to `Text.Word.word_count/2` can be a `String.t`, `File.Stream.t` or `Flow.t` allowing flexible streaming of text.

## English Pluralization

`text` includes an inflector for the English language that takes an approach based upon  [An Algorithmic Approach to English Pluralization](http://users.monash.edu/~damian/papers/HTML/Plurals.html). See the module `Text.Inflect.En` and the functions:

* `Text.Inflect.En.pluralize/2`
* `Text.Inflect.En.pluralize_noun/2`
* `Text.Inflect.En.pluralize_verb/1`
* `Text.Inflect.En.pluralize_adjective/1`

## Language Detection

`text` contains 3 language classifiers to aid in natural language detection. However it does not include any corpora; these are contained in separate libraries. The available classifiers are:

* `Text.Language.Classifier.CommulativeFrequency`
* `Text.Language.Classifier.NaiveBayesian`
* `Text.Language.Classifier.RankOrder`

Additional classifiers can be added by defining a module that implements the `Text.Language.Classifier` behaviour.

The library [text_corpus_udhr](https://hex.pm/packages/text_corpus_udhr) implements the `Text.Corpus` behaviour for the [United National Declaration of Human Rights](https://en.wikipedia.org/wiki/Universal_Declaration_of_Human_Rights) which is available for download in 423 languages from [Unicode](https://unicode.org/udhr/).

See `Text.Language.detect/2`.

## N-Gram generation

The `Text.Ngram` module supports efficient generation of n-grams of length `2` to `7`. See `Text.Ngram.ngram/2`.

## Down the rabbit hole

Text analysis at a fundamental level requires segmenting arbitrary text in any language into characters (graphemes), words and sentences. This is a complex topic covered by the [Unicode text segmentation](https://unicode.org/reports/tr29) standard augmented by localised rules in [CLDR's](https://cldr.unicode.org)  [segmentations](https://unicode-org.github.io/cldr/ldml/tr35-general.html#Segmentations) data.

Therefore in order to provide higher order text analysis the order of development looks like this:

1. Finish the [Unicode regular expression](http://unicode.org/reports/tr18/) engine in [ex_unicode_set](https://github.com/elixir-unicode/unicode_set). Most of the work is complete but compound character classes needs further work.  Unicode regular expressions are required to implement both [Unicode transforms](https://unicode.org/reports/tr35/tr35-general.html#Transforms) and [Unicode segmentation](https://unicode-org/reports/tr25/tr35-general.html#Segmentations)

2. Implement basic Unicode word and sentence segmentation in [ex_unicode_string](https://github.com/elixir-unicode/unicode_string). Grapheme cluster segmentation is available in the standard library as `String.graphemes/1`

3. Add CLDR tailorings for locale-specific segmentation of words and sentences.

4. Finish up the [Snowball](https://snowballstem.org) stemming compiler. There is a lot to do here, only the parser is partially complete.

5. Implement stemming
