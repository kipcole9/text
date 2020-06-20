# Text

Text & language processing for Elixir.  Initial release focuses on:

* [x] n-gram generation from text
* [x] pluralization of english words
* [x] word counting (word freqencies)
* [x] language detection using pluggable classifier backends.

Second phase will focus on:

* Stemming
* tokenization and part-of-speech tagging (at least for english)
* Sentiment analysis

Each of these phases requires prior development. See [below](#down_the_rabbit_hole).

## Installation

```elixir
def deps do
  [
    {:text, "~> 0.2.0"}
  ]
end
```

## Down the rabbit hole

Text analysis at a fundamental level requires segmenting arbitrary text in any language into characters (graphemes), words and sentences. This is a complex topic covered by the [Unicode text segmentation](https://unicode.org/reports/tr29) standard agumented by localised rules in [CLDR's](https://cldr.unicode.org)  [segmentations](https://unicode-org.github.io/cldr/ldml/tr35-general.html#Segmentations) data.

Therefore in order to provide higher order text analysis the order of development looks like this:

1. Finish the [Unicode regular expression](http://unicode.org/reports/tr18/) engine in [ex_unicode_set](https://github.com/elixir-unicode/unicode_set). Most of the work is complete but compound character classes needs further work.  Unicode regular expressions are required to implement both [Unicode transforms](https://unicode.org/reports/tr35/tr35-general.html#Transforms) and [Unicode segmentation](https://unicode-org/reports/tr25/tr35-general.html#Segmentations)

2. Implement basic Unicode word and sentence segmentation in [ex_unicode_string](https://github.com/elixir-unicode/unicode_string). Grapheme cluster segmentation is available in the standard library as `String.graphemes/1`

3. Add CLDR tailorings for locale-specific segmentation of words and sentences.

4. Finish up the [Snowball](https://snowballstem.org) stemming compiler. There is a lot to do here, only the parser is partially complete.

5. Implement stemming
