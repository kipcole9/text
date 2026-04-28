defmodule Text.WordCloud.Backend do
  @moduledoc """
  Behaviour for `Text.WordCloud` scoring backends.

  Each backend takes a pre-tokenized stream of words (or, in the
  case of phrase-aware scorers, the raw text plus options carrying
  the resolved language and stopwords) and returns a list of scored
  candidate terms. The orchestrator in `Text.WordCloud` then
  normalises the raw scores to `[0.0, 1.0]`, sorts, and trims to
  `:max_terms`.

  All backends return scores in **higher-is-better** form. YAKE!,
  whose published score is "lower = more relevant", inverts
  internally before returning so the orchestrator's normalisation
  does not need a per-backend direction flag.

  ### Callback contract

      @callback score(input, options) :: [scored_term()]

  * `input` — the original `text` or `[text]` argument passed to
    `Text.WordCloud.terms/2`. Backends that work in pre-tokenized
    space can call the internal tokenisation helpers under
    `lib/word_cloud/tokens.ex` to share the orchestrator's
    tokenization pipeline.

  * `options` — the *resolved* keyword list. The orchestrator has
    already filled in `:language`, `:stopwords`, `:case_fold`, and
    `:ngram_range`, so backends do not need to re-derive them.

  Each returned tuple is `{term, raw_score, count, kind}` with:

  * `term` — the surface form to display.

  * `raw_score` — a non-negative number, higher = more important.

  * `count` — how many times the term occurs in the input.

  * `kind` — `:word` or `:phrase` (n > 1).

  """

  @type scored_term ::
          {term :: String.t(), raw_score :: number(), count :: pos_integer(),
           kind :: :word | :phrase}

  @callback score(input :: String.t() | [String.t()], options :: keyword()) ::
              [scored_term()]
end
