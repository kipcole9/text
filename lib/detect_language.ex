defmodule Text.DetectLanguage do
  alias Text.Ngram

  @ngram 4
  @no_entry :math.log(5.0e-6)

  def detect_language(text, model \\ corpus_model()) do
    text_ngrams = Ngram.ngram(text, @ngram)
    language_candidates = Enum.map(corpus(), &(elem(&1, 0)))

    language_candidates
    |> Task.async_stream(__MODULE__, :detect_one_language, [model, text_ngrams], async_options())
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(fn {_, {score, _, _}} -> score end)
    |> Enum.reverse
  end

  def detect_one_language(language, model, text_ngrams) do
    language_model = Map.get(model, language)

    score =
      text_ngrams
      |> Enum.reduce({0, 0, 0}, fn {ngram, _count}, {acc, found, not_found} ->
        p1 = if Map.get(language_model, ngram), do: 1, else: 0
        p2 = if p1 == 0, do: 1, else: 0
        probability = Map.get(language_model, ngram) || @no_entry
        {acc + probability, found + p1, not_found + p2}
      end)

    {language, score}
  end

  def async_options do
    [max_concurrency: System.schedulers_online() * 2, ordered: false]
  end

  def build_model do
    model =
      corpus()
      |> Task.async_stream(__MODULE__, :process_corpus_entry, [], async_options())
      |> Enum.map(&elem(&1, 1))
      |> Map.new
      |> :erlang.term_to_binary

    File.write!(corpus_model_file(), model)
  end

  def corpus_model do
    corpus_model_file()
    |> File.read!
    |> :erlang.binary_to_term
  end

  def corpus_model_file do
    Path.join(:code.priv_dir(:text), "detect_language/udhr_ngrams.etf")
  end

  def process_corpus_entry({language, entry}, n \\ @ngram) do
    ngrams =
      corpus_dir()
      |> Path.join(corpus_file(entry))
      |> File.read!
      |> String.split("---")
      |> Enum.at(1)
      |> String.trim
      |> String.normalize(:nfc)
      |> Ngram.ngram(n)
      |> convert_to_probabilities()

    {language, ngrams}
  end

  def convert_to_probabilities(ngrams) do
    sum =
      ngrams
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum

    ngrams
    |> Enum.map(fn {ngram, count} ->
      {ngram, :math.log(count / sum)}
    end)
    |> Map.new
  end

  def corpus_file(%{file: file}) do
    "udhr/udhr_" <> file <> ".txt"
  end

  def corpus_dir do
    "./corpus"
  end

  def corpus do
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

  def language_codes do
    corpus_dir()
    |> Path.join(["language-codes-3b2.json"])
    |> File.read!()
    |> Jason.decode!
    |> Enum.map(fn l -> {l["alpha3-b"], Map.get(l, "alpha2")} end)
    |> Map.new
  end
end