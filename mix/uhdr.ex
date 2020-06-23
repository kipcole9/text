defmodule Text.Language.Udhr do
  @moduledoc """
  Functions to process files from the
  [UDHR corpus](http://research.ics.aalto.fi/cog/data/udhr/).

  """

  @doc false
  def udhr_corpus_file(%{file: file}) do
    "udhr/udhr_" <> file <> ".txt"
  end

  @doc false
  @corpus_dir "./corpus"
  def udhr_corpus_dir do
    @corpus_dir
  end

  import SweetXml

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
  Save the BCP47 names of the languages in which
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

    # |> Text.Language.normalise_text()
  end
end
