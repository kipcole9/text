defmodule Text.Language.Udhr do
  @moduledoc """
  Functions to process files from the
  [UDHR corpus](http://research.ics.aalto.fi/cog/data/udhr/).

  """
  import SweetXml

  @corpus_dir "./corpus"

  @corpus @corpus_dir
          |> Path.join(["udhr/index.xml"])
          |> File.read!()
          |> xpath(~x"//udhrs/udhr"l,
            iso639: ~x"./@iso639-3"s,
            bcp47: ~x"./@bcp47"s,
            script: ~x"./@iso15924"s,
            stage: ~x"./@stage"I,
            name: ~x"./@n"s,
            file: ~x"./@f"s
          )
          |> Enum.map(&Map.pop(&1, :bcp47))
          |> Enum.filter(fn {_k, v} -> v[:stage] >= 4 end)
          |> Map.new()

  @doc false
  def udhr_corpus_file(%{file: file}) do
    "udhr/udhr_" <> file <> ".txt"
  end

  @doc false
  def udhr_corpus_dir do
    @corpus_dir
  end

  @doc """
  Returns the map of the UDHR corpus
  index keyed by the BCP47 language name.

  """
  def udhr_corpus do
    @corpus
  end

  @doc """
  Returns names of the languages in which
  the UDHR corpus is available.

  """
  @known_languages Map.keys(@corpus)
  def known_languages do
    @known_languages
  end

  @doc """
  Save the BCP-47 names of the languages in which
  the UDHR corpus is available.

  """
  @language_file "priv/vocabulary/udhr_languages.etf"
  def save_known_languages do
    File.write!(@language_file, :erlang.term_to_binary(known_languages()))
  end

  def udhr_corpus_content(entry) do
    udhr_corpus_dir()
    |> Path.join(udhr_corpus_file(entry))
    |> File.read!()
    |> String.split("---")
    |> Enum.at(1)
    |> String.trim()
    |> String.replace(~r/\s+/u, " ")

    # Normalizing the corpus would
    # require normalizing input text
    # and its not clear thats an
    # improvement in accuracy
    # |> Text.Language.normalise_text()
  end

  @max_demand 5

  @doc """
  Builds the vocabulary for
  all known vocabulary modules

  """
  def build_vocabularies(options \\ []) do
    max_demand = Keyword.get(options, :max_demand, @max_demand)

    Text.Vocabulary.known_vocabularies()
    |> Enum.each(&build_vocabulary(&1, max_demand: max_demand))
  end

  @doc """
  Builds a vocabulary for a given vocanulary
  module.

  """
  def build_vocabulary(vocabulary_module, options \\ []) do
    ngram_range = vocabulary_module.ngram_range()
    file = vocabulary_module.file()
    max_demand = Keyword.get(options, :max_demand, @max_demand)

    frequency_map_by_language =
      udhr_corpus()
      |> Flow.from_enumerable(max_demand: max_demand)
      |> Flow.map(&Text.Vocabulary.calculate_corpus_ngrams(&1, ngram_range))
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
