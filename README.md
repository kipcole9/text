# Text

Text & language processing for Elixir.  First focus is:

* n-gram generation from text
* pluralization of english words
* language detection using pluggable classifier backends.

Second phase will focus on:

* Stemming (after building a snowball compiler to elixir)
* tokenization and part-of-speech tagging (at least for english)
* Sentiment analysis

## Installation

```elixir
def deps do
  [
    {:text, "~> 0.2.0"}
  ]
end
```

