defmodule Text.Corpus do
  @moduledoc """


  """

  @callback known_vocabularies :: [Text.vocabulary, ...]
  @callback known_languages :: [Text.language, ...]
  @callback language_content(Text.language) :: String.t

  @callback detect(String.t, Keyword.t) :: [Text.frequency_tuple, ...]

  @max_demand 5

  @doc """
  Builds the vocabulary for
  all known vocabulary modules

  """
  def build_vocabularies(corpus, options \\ []) do
    max_demand = Keyword.get(options, :max_demand, @max_demand)

    corpus.known_vocabularies()
    |> Enum.each(&build_vocabulary(&1, max_demand: max_demand))
  end

  @doc """
  Builds a vocabulary for a given vocanulary
  module.

  """
  def build_vocabulary(corpus, vocabulary, options \\ []) do
    ngram_range = vocabulary.ngram_range()
    file = vocabulary.file()
    max_demand = Keyword.get(options, :max_demand, @max_demand)

    frequency_map_by_language =
      corpus.known_languages
      |> Flow.from_enumerable(max_demand: max_demand)
      |> Flow.map(&Text.Vocabulary.calculate_corpus_ngrams(corpus, &1, ngram_range))
      |> Enum.to_list
      |> calculate_global_frequencies
      |> remove_structs_for_space_reduction

    binary = :erlang.term_to_binary(frequency_map_by_language)
    :ok = File.write!(file, binary)

    frequency_map_by_language
  end

  @doc false
  def remove_structs_for_space_reduction(frequency_map) do
    Enum.map(frequency_map, fn {language, ngram_map} ->
      new_ngram_map =
        Enum.map(ngram_map, fn {ngram, stats} -> {ngram, Map.from_struct(stats)} end)
        |> Map.new()

      {language, new_ngram_map}
    end)
    |> Map.new()
  end

  # Calculate the total frequency for each
  # ngram across all regions
  @doc false
  def calculate_global_frequencies(frequency_map_by_language) do
    frequency_map_by_language
    |> invert_to_frequency_map_by_ngram()
    |> calculate_global_frequency_and_rank()
    |> invert_to_frequency_map_by_language()
  end

  # Invert
  #   %{language => %{ngram => frequencies}}
  # to:
  #   %{ngram => %{language => frequencies}}
  @doc false
  def invert_to_frequency_map_by_ngram(frequency_map_by_language) do
    Enum.reduce(frequency_map_by_language, %{}, fn {language, ngrams}, acc ->
      Enum.reduce(ngrams, acc, fn {ngram, ngram_stats}, acc2 ->
        Map.update(acc2, ngram, %{language => ngram_stats}, &Map.put(&1, language, ngram_stats))
      end)
    end)
  end

  # Invert
  #   %{ngram => %{language => frequencies}}
  # to:
  #   %{language => %{ngram => frequencies}}
  @doc false
  def invert_to_frequency_map_by_language(frequency_map_by_ngram) do
    Enum.reduce(frequency_map_by_ngram, %{}, fn {ngram, languages}, acc ->
      Enum.reduce(languages, acc, fn {language, ngram_stats}, acc2 ->
        Map.update(acc2, language, %{ngram => ngram_stats}, &Map.put(&1, ngram, ngram_stats))
      end)
    end)
  end

  # Calculate the frequencies across all regions
  # and then the global range across all region
  @doc false
  def calculate_global_frequency_and_rank(frequency_map_by_ngram) do
    Enum.map(frequency_map_by_ngram, fn {ngram, ngram_by_language} ->
      total_count_for_ngram = total_ngram_count_for_languages(ngram_by_language)

      added_global_stats =
        Enum.map(ngram_by_language, fn {language, ngram_stats} ->
          {language, %{ngram_stats | global_frequency: ngram_stats.count / total_count_for_ngram}}
        end)
        |> Enum.sort(&(elem(&1, 1).global_frequency > elem(&2, 1).global_frequency))
        |> Enum.with_index(1)
        |> Enum.map(fn {{language, ngram_stats}, global_rank} ->
          {language, %{ngram_stats | global_rank: global_rank}}
        end)

      {ngram, added_global_stats}
    end)
  end

  @doc false
  def total_ngram_count_for_languages(ngram_by_language) do
    Enum.reduce(ngram_by_language, 0, fn {_language, %{count: count}}, acc ->
      acc + count
    end)
  end
end