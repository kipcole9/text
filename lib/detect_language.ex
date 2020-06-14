defmodule Text.Detect do
  alias Text.Ngram

# http://practicalcryptography.com/miscellaneous/machine-learning/tutorial-automatic-language-identification-ngram-b/

  @ngram 4
  @no_entry :math.log(5.0e-6)
  @persistent_key :detect_language
  @max_ngrams 300

  @doc false
  def max_ngrams do
    @max_ngrams
  end

  @doc false
  def ngram_max_size do
    @ngram
  end

  def detect_language(text, options \\ []) when is_binary(text) do
    language_candidates = Keyword.get(options, :only)

    text
    |> detect_languages(language_candidates)
    |> process_return(options)
  end

  def process_return({:error, _} = error, _) do
    error
  end

  def process_return(result, options) do
    if options[:alpha2] do
      {language, _} = Enum.find(result, &Text.Iso639.to_iso639_two(elem(&1, 0)))
      Text.Iso639.to_iso639_two(language)
    else
      [{language, _} | _rest] = result
      language
    end
  end

  @doc false
  def detect_languages(text, language_candidates \\ nil)

  def detect_languages(text, nil) when is_binary(text) do
    ensure_model_is_initialized!()
    language_candidates = :persistent_term.get({@persistent_key, :languages})
    do_detect_language(text, language_candidates)
  end

  @doc false
  def detect_languages(text, language_candidates)
      when is_binary(text) and is_list(language_candidates) do

    language_candidates = Enum.map(language_candidates,
      &(Text.Iso639.to_iso639_three(&1) || &1))

    ensure_model_is_initialized!()
    all_languages = :persistent_term.get({@persistent_key, :languages})
    not_known = Enum.filter(language_candidates, &(&1 not in all_languages)) |> IO.inspect

    if not_known == [] do
      do_detect_language(text, language_candidates)
    else
      {:error, {ArgumentError, "Language candidates #{inspect not_known} are not known"}}
    end
  end

  defp do_detect_language(text, language_candidates) do
    text_ngrams = ngrams(text, 2..ngram_max_size())

    language_candidates
    |> Task.async_stream(__MODULE__, :detect_one_language, [text_ngrams], async_options())
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort(fn {_, {score1, _, _}}, {_, {score2, _, _}} -> score1 >= score2 end)
  end

  @doc false
  def detect_one_language(language, text_ngrams) do
    language_model = :persistent_term.get({@persistent_key, language})

    score =
      text_ngrams
      |> Enum.reduce({0, 0, 0}, fn {ngram, _count}, {acc, found, not_found} ->
        probability = Map.get(language_model, ngram)
        {p1, p2} = if probability, do: {1, 0}, else: {0, 1}
        probability = probability || @no_entry
        {acc + probability, found + p1, not_found + p2}
      end)

    {language, score}
  end

  defp ngrams(text, range) do
    Enum.flat_map(range, &Ngram.ngram(text, &1))
    |> Enum.sort(fn {_, weight1}, {_, weight2} -> weight1 >= weight2 end)
    |> Enum.take(@max_ngrams)
  end

  defp async_options do
    [max_concurrency: System.schedulers_online() * 2, ordered: false]
  end

  defp ensure_model_is_initialized! do
    :persistent_term.get({@persistent_key, :languages}, nil) || load_corpus_model()
  end

  @doc false
  def load_corpus_model do
    model =
      corpus_model_file()
      |> File.read!
      |> :erlang.binary_to_term

    Enum.each(model, fn {language, ngrams} ->
      :persistent_term.put({@persistent_key, language}, ngrams)
    end)

    languages = Map.keys(model)
    :persistent_term.put({@persistent_key, :languages}, languages)
  end

  defp corpus_model_file do
    Path.join(:code.priv_dir(:text), "detect_language/udhr_ngrams.etf")
  end
end