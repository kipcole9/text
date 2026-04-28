defmodule Text.WordCloud.Backends.Frequency do
  @moduledoc """
  Trivial frequency-counting backend for `Text.WordCloud`.

  Returns each candidate term's raw occurrence count as its score. The
  resulting cloud is dominated by whatever survives the stopword
  filter — useful as a sanity-check baseline and for inputs where
  there is genuinely no reference corpus to compare against, but
  almost always less informative than `Text.WordCloud.Backends.YAKE`
  for English-style text.

  Honours the orchestrator's `:ngram_range`, `:case_fold`,
  `:stopwords`, and `:language` options. The returned `:weight` after
  normalisation is `count / max_count`.

  """

  @behaviour Text.WordCloud.Backend

  alias Text.WordCloud.Tokens

  @impl true
  def score(input, options) do
    {min_n, max_n} = Keyword.get(options, :ngram_range, {1, 1})

    %{sentences: sentences} = Tokens.prepare(input, options)

    sentences
    |> Tokens.candidates(min_n, max_n)
    |> Tokens.count_candidates()
    |> Enum.map(fn {tokens, count, kind} ->
      {Enum.join(tokens, " "), count, count, kind}
    end)
  end
end
