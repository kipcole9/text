defmodule Text.LangDetect.Model do
  @moduledoc false
  alias Text.Ngram

  @ngram Text.Detect.ngram_max_size
  @max_ngrams Text.Detect.max_ngrams

  def build_model do
    model =
      corpus()
      |> Task.async_stream(__MODULE__, :process_corpus_entry, [], async_options())
      |> Enum.map(&elem(&1, 1))
      |> Map.new
      |> :erlang.term_to_binary

    File.write!(corpus_model_file(), model)
  end

  defp corpus_model_file do
    Path.join(:code.priv_dir(:text), "detect_language/udhr_ngrams.etf")
  end

  @doc false
  def process_corpus_entry({language, entry}, n \\ @ngram) do
    ngrams =
      corpus_dir()
      |> Path.join(corpus_file(entry))
      |> File.read!
      |> String.split("---")
      |> Enum.at(1)
      |> String.trim
      |> String.normalize(:nfc)
      |> ngrams(2..n)
      |> convert_to_probabilities()

    {language, ngrams}
  end

  def ngrams(text, range) do
    Enum.flat_map(range, &Ngram.ngram(text, &1))
  end

  defp convert_to_probabilities(ngrams) do
    sum =
      ngrams
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum

    ngrams
    |> Enum.map(fn {ngram, count} ->
      {ngram, :math.log(count / sum)}
    end)
    |> Enum.sort(fn {_, weight1}, {_, weight2} -> weight1 >= weight2 end)
    |> Enum.take(@max_ngrams)
    |> Map.new
  end

  defp corpus_file(%{file: file}) do
    "udhr/udhr_" <> file <> ".txt"
  end

  defp corpus_dir do
    "./corpus"
  end

  defp corpus do
    import SweetXml

    corpus_dir()
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
    |> Enum.map(&Map.pop(&1, :iso639))
    |> Enum.filter(fn {_k, v} -> v[:stage] >= 4 end)
    |> Map.new
  end

  @doc false
  def language_codes do
    corpus_dir()
    |> Path.join(["language-codes-3b2.json"])
    |> File.read!()
    |> Jason.decode!
    |> Enum.map(fn l -> {l["alpha3-b"], Map.get(l, "alpha2")} end)
    |> Map.new
  end

  defp async_options do
    [max_concurrency: System.schedulers_online() * 2, ordered: false]
  end
end