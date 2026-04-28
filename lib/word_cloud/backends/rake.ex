defmodule Text.WordCloud.Backends.RAKE do
  @moduledoc """
  RAKE (Rapid Automatic Keyword Extraction) backend for `Text.WordCloud`.

  RAKE is a classic, language-agnostic keyword extractor (Rose et al.,
  2010). It splits the text on stopwords and punctuation to produce
  candidate phrases, then scores each member word by the ratio of its
  total degree (cumulative phrase length) to its raw frequency. A
  phrase score is the sum of its member word scores.

  Higher scores = more important. The result naturally surfaces multi-
  word phrases, since phrases that consist exclusively of distinctive
  content words score above the sum of their parts.

  ### Strengths

  * No reference corpus.

  * Phrase-aware by construction.

  * Trivially multilingual via the stopword swap (uses `Text.Stopwords`
    for the resolved language).

  ### Caveats

  * Quality is sensitive to stopword-list completeness — under-filtering
    produces bloated, low-quality phrases.

  * Tends to over-rank phrases composed of low-frequency words; YAKE!
    is usually a better default.

  ### Options

  Honours the orchestrator's `:language`, `:stopwords`, `:case_fold`,
  and `:locale`. RAKE's candidates are determined by stopword
  boundaries; `:ngram_range` is honoured as a post-filter on the
  resulting phrase lengths.

  """

  @behaviour Text.WordCloud.Backend

  alias Text.Segment

  @impl true
  def score(input, options) do
    {min_n, max_n} = Keyword.get(options, :ngram_range, {1, 3})
    case_fold? = Keyword.get(options, :case_fold, true)
    locale = Keyword.get(options, :locale)
    stopwords = resolve_stopwords(options)

    sentences = tokenise_sentences(input, locale)

    folded_sentences =
      sentences
      |> Enum.map(fn tokens ->
        if case_fold?, do: Enum.map(tokens, &String.downcase/1), else: tokens
      end)

    phrases =
      folded_sentences
      |> Enum.flat_map(&split_on_stopwords(&1, stopwords))
      |> Enum.filter(fn phrase ->
        n = length(phrase)
        n >= min_n and n <= max_n
      end)

    word_scores = compute_word_scores(phrases)

    phrases
    |> count_phrases()
    |> Enum.map(fn {tokens, count} ->
      kind = if length(tokens) == 1, do: :word, else: :phrase
      score = phrase_score(tokens, word_scores)
      {Enum.join(tokens, " "), score, count, kind}
    end)
  end

  # ---- tokenisation ----------------------------------------------------

  defp tokenise_sentences(input, locale) when is_binary(input),
    do: tokenise_sentences([input], locale)

  defp tokenise_sentences(documents, locale) when is_list(documents) do
    documents
    |> Enum.flat_map(fn text ->
      text
      |> normalise_whitespace()
      |> split_sentences(locale)
      |> Enum.map(&split_words(&1, locale))
    end)
    |> Enum.reject(&(&1 == []))
  end

  # `unicode_string`'s sentence segmenter treats newlines as sentence
  # boundaries (per UAX #29), which spuriously fragments multi-line
  # input pasted from documents. Collapse all whitespace runs to a
  # single space before segmenting so sentence boundaries come from
  # punctuation alone.
  defp normalise_whitespace(text), do: String.replace(text, ~r/\s+/u, " ")

  defp split_sentences(text, nil), do: Segment.sentences(text)
  defp split_sentences(text, locale), do: Segment.sentences(text, locale: locale)

  # RAKE treats punctuation as phrase boundaries (per Rose et al. 2010),
  # so we ask the segmenter to keep punctuation tokens — the boundary
  # logic in `split_on_stopwords/2` then treats them the same way it
  # treats stopwords.
  defp split_words(text, nil), do: Segment.words(text, punctuation: :keep)
  defp split_words(text, locale), do: Segment.words(text, locale: locale, punctuation: :keep)

  # Punctuation-only token: every grapheme is in a Unicode punctuation
  # or symbol class. Apostrophes inside contractions ("don't") do not
  # match because they're embedded in alphabetic tokens by UAX #29.
  defp punctuation?(token) do
    Regex.match?(~r/^[\p{P}\p{S}]+$/u, token)
  end

  defp resolve_stopwords(options) do
    case Keyword.get(options, :stopwords, :auto) do
      :none ->
        MapSet.new()

      :auto ->
        language = Keyword.get(options, :language)

        cond do
          is_nil(language) -> MapSet.new()
          Text.Stopwords.available?(language) -> Text.Stopwords.for(language)
          true -> MapSet.new()
        end

      {:extend, extras} ->
        language = Keyword.get(options, :language)

        if language && Text.Stopwords.available?(language) do
          Text.Stopwords.extend(language, extras)
        else
          MapSet.new(extras)
        end

      %MapSet{} = set ->
        set

      list when is_list(list) ->
        MapSet.new(list)
    end
  end

  # ---- candidate phrases -----------------------------------------------

  # Walks a token sequence and emits every maximal run of non-stopword
  # tokens. Stopwords (and punctuation, which the segmenter already
  # drops in `:drop` mode) act as boundaries.
  defp split_on_stopwords(tokens, stopwords) do
    {phrases, current} =
      Enum.reduce(tokens, {[], []}, fn token, {acc, current} ->
        if MapSet.member?(stopwords, token) or punctuation?(token) do
          if current == [], do: {acc, []}, else: {[Enum.reverse(current) | acc], []}
        else
          {acc, [token | current]}
        end
      end)

    if current == [],
      do: Enum.reverse(phrases),
      else: Enum.reverse([Enum.reverse(current) | phrases])
  end

  # ---- per-word scoring ------------------------------------------------

  # word_score(w) = degree(w) / freq(w)
  #
  # degree(w) = sum over phrases p containing w of length(p)
  # freq(w) = number of phrases containing w (counted with multiplicity)
  defp compute_word_scores(phrases) do
    {degree, frequency} =
      Enum.reduce(phrases, {%{}, %{}}, fn phrase, {deg, freq} ->
        phrase_length = length(phrase)

        {deg2, freq2} =
          Enum.reduce(phrase, {deg, freq}, fn word, {d, f} ->
            {Map.update(d, word, phrase_length, &(&1 + phrase_length)),
             Map.update(f, word, 1, &(&1 + 1))}
          end)

        {deg2, freq2}
      end)

    Map.new(degree, fn {word, deg} ->
      f = Map.fetch!(frequency, word)
      {word, deg / f}
    end)
  end

  defp phrase_score(tokens, word_scores) do
    tokens
    |> Enum.map(&Map.get(word_scores, &1, 0.0))
    |> Enum.sum()
  end

  defp count_phrases(phrases) do
    phrases
    |> Enum.reduce({%{}, []}, fn phrase, {counts, order} ->
      case Map.fetch(counts, phrase) do
        {:ok, _} -> {Map.update!(counts, phrase, &(&1 + 1)), order}
        :error -> {Map.put(counts, phrase, 1), [phrase | order]}
      end
    end)
    |> then(fn {counts, order} ->
      order
      |> Enum.reverse()
      |> Enum.map(fn phrase -> {phrase, Map.fetch!(counts, phrase)} end)
    end)
  end
end
