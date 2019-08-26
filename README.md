# Text

Text & language processing for Elixir.  First focus is:

* ngram generation from text
* language detection using pluggable detection backends.  Includes a naive Bayesian classifier.

Second phase will focus on:

* Stemming (after building a snowball compiler to elixir)
* tokenization and part-of-speech tagging (at least for english)
* Sentiment analysis

## Installation

```elixir
def deps do
  [
    {:text, "~> 0.1.0"}
  ]
end
```

