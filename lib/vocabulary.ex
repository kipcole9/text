defmodule Text.Vocabulary do
  @moduledoc """
  A vocabulary is the encoded form of
  a training text that is used to support
  language matching.

  A vocabulary is mapping of an
  n-gram to its rank and probability.

  """
  alias Text.Ngram

  @type t :: module()

  @callback get_vocabulary(String.t()) :: map()
  @callback filename() :: String.t()
  @callback calculate_ngrams(String.t()) :: map()
  @callback ngram_range() :: Range.t()
  @callback load_vocabulary! :: map()

  @max_ngrams 300

  def known_vocabularies(corpus) do
    corpus.known_vocabularies
  end

  @doc """
  Get the vocabulary entry for
  a given language and vocabulary

  """
  def get_vocabulary(vocabulary, language) do
    :persistent_term.get({vocabulary, language}, nil)
  end

  @doc """
  Loads the given vocabulary.

  Vocabularies are placed in
  `:persistent_store` since this
  reduces memory copies and has efficient
  multi-process access.

  """
  def load_vocabulary!(vocabulary) do
    vocabulary_content =
      vocabulary.filename
      |> File.read!()
      |> :erlang.binary_to_term()
      |> structify_ngram_stats

    for {language, ngrams} <- vocabulary_content do
      :persistent_term.put({vocabulary, language}, ngrams)
    end

    :persistent_term.put({vocabulary, :languages}, Map.keys(vocabulary_content))
    vocabulary_content
  end

  defp structify_ngram_stats(ngram_by_language) do
    Enum.map(ngram_by_language, fn {language, ngram_map} ->
      new_ngram_map =
        Enum.map(ngram_map, fn {ngram, stats} ->
          {ngram, struct(Text.Ngram.Frequency, stats)}
        end)
        |> Map.new()

      {language, new_ngram_map}
    end)
    |> Map.new()
  end

  @doc """
  Rerturns a list of the top n
  vocabulary entries by rank for a
  given language and vocabulary.

  This function is primarily intended
  for debugging support.

  """
  def top_n(vocabulary, language, n) do
    vocabulary.filename
    |> File.read!()
    |> :erlang.binary_to_term()
    |> Map.fetch!(language)
    |> top_n(n)
  end

  @doc """
  Returns the top n by rank for a list
  of entries for a given languages
  vocabulary

  """
  def top_n(language_vocabulary, n \\ @max_ngrams) do
    language_vocabulary
    |> Enum.sort(fn {_, %{rank: rank1}}, {_, %{rank: rank2}} -> rank1 < rank2 end)
    |> Enum.take(n)
  end

  @doc """
  Returns the ngrams for a given
  text and range representing
  a range of n-grams

  """
  def get_ngrams(content, from..to) do
    for n <- from..to do
      Ngram.ngram(content, n)
    end
    |> merge_maps
  end

  defp merge_maps([a]) do
    a
  end

  defp merge_maps([a, b]) do
    Map.merge(a, b)
  end

  defp merge_maps([a, b | rest]) do
    merge_maps([Map.merge(a, b) | rest])
  end

  def calculate_corpus_ngrams(corpus, language, range) do
    ngrams =
      language
      |> corpus.language_content
      |> corpus.normalize_text
      |> calculate_ngrams(range)

    {language, ngrams}
  end

  @doc """
  Calculate the n-grams for a given text

  A range of n-grams is calculated from
  `range` and the top `n` ranked
  n-grams from the text are returned

  """

  def calculate_ngrams(content, range, top_n \\ @max_ngrams) when is_binary(content) do
    content
    |> get_ngrams(range)
    |> add_statistics()
    |> order_by_count()
    |> Enum.with_index(1)
    |> Enum.map(fn {{ngram, ngram_stats}, rank} ->
      {ngram, %{ngram_stats | rank: rank}}
    end)
    |> top_n(top_n)
    |> Map.new()
  end

  @doc false
  def order_by_count(ngrams) do
    Enum.sort(ngrams, fn
      {ngram1, %{count: count}}, {ngram2, %{count: count}} -> ngram1 > ngram2
      {_, %{count: count1}}, {_, %{count: count2}} -> count1 > count2
    end)
  end

  # For each n-gram keep the count,
  # frequency and log of the frequency
  defp add_statistics(ngrams) do
    total_count =
      ngrams
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()

    ngrams
    |> Enum.map(fn {ngram, count} ->
      frequency = count / total_count

      {ngram,
       %Text.Ngram.Frequency{
         count: count,
         frequency: frequency,
         log_frequency: :math.log(frequency)
       }}
    end)
  end
end
