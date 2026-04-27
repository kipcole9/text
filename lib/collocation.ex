defmodule Text.Collocation do
  @moduledoc """
  Extract statistically significant word bigrams from a token stream.

  Given a sequence of tokens (or a string that gets tokenised), returns
  the bigrams that occur together more often than chance would predict.
  Useful for surfacing multi-word expressions ("New York", "machine
  learning"), finding domain-specific phrases in a corpus, and as a
  pre-processing step for higher-order analytics.

  ### Association measures

  Three measures are supported:

  * `:frequency` — raw bigram count. Cheapest baseline; biased toward
    high-frequency stop-word pairs.

  * `:pmi` — pointwise mutual information,
    `log(P(a,b) / (P(a) · P(b)))`. Highlights pairs that appear
    together far more than independence predicts. Sensitive to rare
    pairs, so combine with `:min_count`.

  * `:log_likelihood` — Dunning's log-likelihood ratio (G²). Less
    sensitive to rare-pair noise than PMI; the standard choice in
    corpus linguistics.

  ### Defaults

  By default, `bigrams/2` lower-cases tokens, drops bigrams that
  appear fewer than 3 times, and ranks by `:log_likelihood`. Override
  via the keyword options.

  """

  alias Text.Segment

  @typedoc "An association measure used to rank bigrams."
  @type measure :: :frequency | :pmi | :log_likelihood

  @typedoc "A token bigram represented as a 2-element list."
  @type bigram :: [String.t()]

  @doc """
  Returns the most strongly-associated bigrams in `input`.

  ### Arguments

  * `input` is either:
    * a string (tokenised via the `:tokenizer` option), or
    * a pre-tokenised list of strings (treated as a single contiguous
      token stream).

  ### Options

  * `:measure` — `:frequency`, `:pmi`, or `:log_likelihood`. Defaults
    to `:log_likelihood`.

  * `:min_count` — drops bigrams with raw count below this. Defaults
    to `3`. Keeps PMI and friends from being dominated by once-seen
    rare-pair noise.

  * `:k` — number of results. Defaults to `20`. Pass `:infinity` to
    return all bigrams that pass `:min_count`.

  * `:tokenizer` — string-to-tokens function used when `input` is a
    string. Defaults to `&Text.Segment.words/1`.

  * `:fold_case` — when `true` (default), tokens are lowercased.

  * `:stopwords` — a list or `MapSet` of tokens to exclude from
    bigrams. A bigram with either side in the stopword set is dropped.
    Defaults to `[]`.

  ### Returns

  * A list of `{bigram, score}` tuples sorted by score descending,
    where `bigram` is a two-element list.

  ### Examples

      iex> tokens = ~w[the cat sat on the mat the cat ran fast the cat slept]
      iex> [{top_bigram, _score} | _] =
      ...>   Text.Collocation.bigrams(tokens, min_count: 2, k: 5)
      iex> top_bigram
      ["the", "cat"]

      iex> Text.Collocation.bigrams("a a a", min_count: 1, measure: :frequency)
      [{["a", "a"], 2}]

  """
  @spec bigrams(String.t() | [String.t()], keyword()) :: [{bigram(), number()}]
  def bigrams(input, options \\ []) do
    measure = Keyword.get(options, :measure, :log_likelihood)
    min_count = Keyword.get(options, :min_count, 3)
    k = Keyword.get(options, :k, 20)
    tokenizer = Keyword.get(options, :tokenizer, &Segment.words/1)
    fold_case? = Keyword.get(options, :fold_case, true)
    stopwords = Keyword.get(options, :stopwords, []) |> MapSet.new()

    tokens =
      input
      |> tokenize(tokenizer)
      |> maybe_fold_case(fold_case?)
      |> Enum.reject(&MapSet.member?(stopwords, &1))

    {bigram_counts, unigram_counts, total_bigrams} = count(tokens)

    bigram_counts
    |> Enum.filter(fn {_pair, count} -> count >= min_count end)
    |> Enum.map(fn {pair, count} ->
      score = score_pair(measure, pair, count, unigram_counts, total_bigrams)
      {pair, score}
    end)
    |> Enum.sort_by(fn {_pair, score} -> -score end)
    |> take(k)
  end

  # ---- internal ---------------------------------------------------------

  defp tokenize(input, tokenizer) when is_binary(input), do: tokenizer.(input)
  defp tokenize(tokens, _tokenizer) when is_list(tokens), do: tokens

  defp maybe_fold_case(tokens, false), do: tokens
  defp maybe_fold_case(tokens, true), do: Enum.map(tokens, &String.downcase/1)

  # Walk the token stream once, building unigram and bigram counts.
  defp count(tokens) do
    unigrams = count_terms(tokens)

    bigrams =
      tokens
      |> Enum.chunk_every(2, 1, :discard)
      |> count_terms()

    {bigrams, unigrams, max(length(tokens) - 1, 0)}
  end

  defp count_terms(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      Map.update(acc, item, 1, &(&1 + 1))
    end)
  end

  # ---- measures ---------------------------------------------------------

  defp score_pair(:frequency, _pair, count, _unigrams, _total), do: count

  defp score_pair(:pmi, [a, b], count, unigrams, total) do
    p_ab = count / total
    p_a = (Map.get(unigrams, a) || 0) / total
    p_b = (Map.get(unigrams, b) || 0) / total

    if p_a == 0 or p_b == 0 do
      0.0
    else
      :math.log(p_ab / (p_a * p_b))
    end
  end

  defp score_pair(:log_likelihood, [a, b], k11, unigrams, total) do
    # 2x2 contingency table:
    #   k11 = count(a, b)            — bigram observed
    #   k12 = count(a, ¬b)           — a followed by non-b
    #   k21 = count(¬a, b)           — non-a followed by b
    #   k22 = count(¬a, ¬b)          — neither
    n_a = Map.get(unigrams, a) || 0
    n_b = Map.get(unigrams, b) || 0

    k12 = max(n_a - k11, 0)
    k21 = max(n_b - k11, 0)
    k22 = max(total - k11 - k12 - k21, 0)

    2 *
      (xlogx(k11) + xlogx(k12) + xlogx(k21) + xlogx(k22) - xlogx(k11 + k12) -
         xlogx(k11 + k21) - xlogx(k12 + k22) - xlogx(k21 + k22) + xlogx(total))
  end

  defp xlogx(0), do: 0.0
  defp xlogx(n) when is_integer(n) and n > 0, do: n * :math.log(n)

  # ---- top-k ------------------------------------------------------------

  defp take(list, :infinity), do: list
  defp take(list, k) when is_integer(k) and k >= 0, do: Enum.take(list, k)
end
