defmodule Text.Language.Udhr do

  def udhr_corpus_file(%{file: file}) do
    "udhr/udhr_" <> file <> ".txt"
  end

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
    |> Map.new

  def udhr_corpus do
    @corpus
  end

  @known_languages Map.keys(@corpus)
  def known_languages do
    @known_languages
  end

  def udhr_corpus_content(entry) do
    udhr_corpus_dir()
    |> Path.join(udhr_corpus_file(entry))
    |> File.read!
    |> String.split("---")
    |> Enum.at(1)
    |> String.trim
    |> Text.Language.normalise_text()
  end
end