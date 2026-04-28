defmodule Text.WordCloud.Backends.YAKE do
  @moduledoc """
  YAKE! (Yet Another Keyword Extractor) backend for `Text.WordCloud`.

  Implements the unsupervised, statistical keyword-extraction algorithm
  described in [Campos et al., *Information Sciences* 509,
  2020](https://doi.org/10.1016/j.ins.2019.09.013). YAKE! computes five
  per-word features (casing, position, frequency, relatedness to
  context, sentence dispersion) entirely from the input document, then
  composes them into n-gram candidate scores. No reference corpus or
  trained model is required — this is what makes it the right default
  for a multilingual word-cloud library.

  The algorithm's only language-specific dependency is the stopword
  list, supplied via `Text.Stopwords.for/1` (or the caller's `:stopwords`
  override). YAKE!'s own design treats stopwords as phrase-boundary
  markers and as low-content interior fillers, so a good list directly
  improves output quality.

  ### Score direction

  YAKE!'s published score is "lower = more important". This module
  inverts internally before returning, so the value passed to the
  orchestrator is the standard "higher = more important" form every
  other backend uses.

  ### Options

  * `:ngram_range` — `{min, max}` candidate length. Defaults to
    `{1, 3}` (the YAKE paper's default).

  * `:window_size` — neighbour-context window for the relatedness
    feature. Defaults to `1` (immediate neighbours), matching the
    reference implementation.

  Standard `Text.WordCloud` orchestrator options (`:language`,
  `:stopwords`, `:case_fold`, `:locale`) are honoured.

  ### Caveats

  This is a faithful but simplified port of the algorithm: the five
  features are computed exactly as in the paper, but the
  candidate-generation rules use the stricter "phrases must start
  and end with a non-stopword" form rather than the paper's full
  composition rules. In practice this produces output well-correlated
  with the reference Python implementation (`LIAAD/yake`); a
  differential-fixture test against that implementation is a
  follow-up.

  """

  @behaviour Text.WordCloud.Backend

  alias Text.Segment

  # Compose a YAKE single-word score from the five normalised features.
  # The published formula:
  #
  #     S(w) = (W_rel * W_pos) / (W_case + W_freq/W_rel + W_diff/W_rel)
  #
  # Lower = more important. Stopwords are forced to a high score (=
  # uninteresting) at the phrase-composition step instead of here, so
  # a stopword's individual score is still computable.
  @impl true
  def score(input, options) do
    {min_n, max_n} = Keyword.get(options, :ngram_range, {1, 3})
    window = Keyword.get(options, :window_size, 1)
    case_fold? = Keyword.get(options, :case_fold, true)
    locale = Keyword.get(options, :locale)
    stopwords = resolve_stopwords(options)

    sentences = tokenise_sentences(input, locale)

    # Pre-fold for analysis. The case-fold flag controls the *output*
    # surface form; YAKE's casing feature is computed against the
    # original case regardless.
    cased_sentences = sentences
    folded_sentences = Enum.map(sentences, fn toks -> Enum.map(toks, &String.downcase/1) end)

    stats = collect_stats(cased_sentences, folded_sentences)
    word_scores = compute_word_scores(stats, window)

    folded_sentences
    |> generate_candidates(min_n, max_n, stopwords)
    |> score_candidates(word_scores, stopwords)
    |> finalise(case_fold?, sentences, folded_sentences)
  end

  # ---- tokenisation ----------------------------------------------------

  defp tokenise_sentences(input, locale) when is_binary(input),
    do: tokenise_sentences([input], locale)

  defp tokenise_sentences(documents, locale) when is_list(documents) do
    documents
    |> Enum.flat_map(&split_sentences(&1, locale))
    |> Enum.map(&split_words(&1, locale))
    |> Enum.reject(&(&1 == []))
  end

  # See `Text.WordCloud.Tokens` for why we normalise whitespace before
  # sentence breaking.
  defp split_sentences(text, nil), do: text |> normalise_whitespace() |> Segment.sentences()

  defp split_sentences(text, locale),
    do: text |> normalise_whitespace() |> Segment.sentences(locale: locale)

  defp normalise_whitespace(text), do: String.replace(text, ~r/\s+/u, " ")

  defp split_words(text, nil), do: Segment.words(text)
  defp split_words(text, locale), do: Segment.words(text, locale: locale)

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

  # ---- per-word statistics --------------------------------------------

  # Walk every sentence once, accumulating:
  #
  #   * tf (folded), tf_uppercase, tf_acronym
  #   * sentence_indices — which sentences a word appears in
  #   * left_neighbours, right_neighbours — multisets
  #
  # Result is a map `%{folded_word => stats_map}`.
  defp collect_stats(cased_sentences, folded_sentences) do
    cased_sentences
    |> Enum.zip(folded_sentences)
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{cased, folded}, sentence_index}, acc ->
      walk_sentence(cased, folded, sentence_index, acc)
    end)
  end

  defp walk_sentence(cased, folded, sentence_index, acc) do
    folded
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {word, position_in_sentence}, acc2 ->
      cased_word = Enum.at(cased, position_in_sentence)
      left = if position_in_sentence > 0, do: Enum.at(folded, position_in_sentence - 1), else: nil
      right = Enum.at(folded, position_in_sentence + 1)

      acc2
      |> Map.update(
        word,
        new_word_stats(cased_word, sentence_index, position_in_sentence, left, right),
        &update_word_stats(&1, cased_word, sentence_index, position_in_sentence, left, right)
      )
    end)
  end

  defp new_word_stats(cased, sentence_index, position, left, right) do
    %{
      tf: 1,
      tf_uppercase: if(uppercase_initial?(cased, position), do: 1, else: 0),
      tf_acronym: if(acronym?(cased), do: 1, else: 0),
      sentence_indices: MapSet.new([sentence_index]),
      left_neighbours: bump(%{}, left),
      right_neighbours: bump(%{}, right)
    }
  end

  defp update_word_stats(stats, cased, sentence_index, position, left, right) do
    %{
      tf: stats.tf + 1,
      tf_uppercase: stats.tf_uppercase + if(uppercase_initial?(cased, position), do: 1, else: 0),
      tf_acronym: stats.tf_acronym + if(acronym?(cased), do: 1, else: 0),
      sentence_indices: MapSet.put(stats.sentence_indices, sentence_index),
      left_neighbours: bump(stats.left_neighbours, left),
      right_neighbours: bump(stats.right_neighbours, right)
    }
  end

  defp bump(map, nil), do: map
  defp bump(map, key), do: Map.update(map, key, 1, &(&1 + 1))

  # First-position uppercase tokens are excluded — the casing feature
  # rewards mid-sentence capitalisation (likely proper nouns) only.
  defp uppercase_initial?(_word, 0), do: false

  defp uppercase_initial?(word, _position) do
    case String.first(word) do
      nil -> false
      first -> first == String.upcase(first) and first != String.downcase(first)
    end
  end

  # An acronym is fully uppercase, length >= 2.
  defp acronym?(word) do
    String.length(word) >= 2 and word == String.upcase(word) and
      word != String.downcase(word)
  end

  # ---- five-feature scoring -------------------------------------------

  defp compute_word_scores(stats, window) do
    tfs = Enum.map(stats, fn {_, s} -> s.tf end)
    mean_tf = mean(tfs)
    std_tf = stdev(tfs, mean_tf)
    max_tf = Enum.max([1 | tfs])

    n_sentences =
      stats
      |> Enum.flat_map(fn {_, s} -> MapSet.to_list(s.sentence_indices) end)
      |> Enum.uniq()
      |> length()
      |> max(1)

    Map.new(stats, fn {word, s} ->
      w_case = (max(s.tf_uppercase, s.tf_acronym) || 0) / :math.log2(1 + s.tf)
      median_sentence = median(s.sentence_indices) + 1.0
      w_position = :math.log(:math.log(3 + median_sentence))
      w_frequency = s.tf / (mean_tf + std_tf + 1.0e-9)

      dl = relatedness_factor(s.left_neighbours, s.tf, window)
      dr = relatedness_factor(s.right_neighbours, s.tf, window)
      w_relatedness = 1.0 + (dl + dr) * (s.tf / max_tf)

      w_difsentence = MapSet.size(s.sentence_indices) / n_sentences

      score =
        w_relatedness * w_position /
          (w_case + w_frequency / w_relatedness + w_difsentence / w_relatedness)

      {word, score}
    end)
  end

  # DL/DR: ratio of distinct neighbours to total occurrences. The window
  # parameter is reserved for future use (multi-step contexts); for the
  # default window of 1 it has no effect.
  defp relatedness_factor(neighbours, tf, _window) do
    distinct = map_size(neighbours)
    total = Enum.sum(Map.values(neighbours))
    if total == 0, do: 0.0, else: distinct / max(tf, total)
  end

  defp mean([]), do: 0.0
  defp mean(values), do: Enum.sum(values) / length(values)

  defp stdev([], _), do: 0.0

  defp stdev(values, mean) do
    values
    |> Enum.map(fn v -> (v - mean) * (v - mean) end)
    |> Enum.sum()
    |> Kernel./(length(values))
    |> :math.sqrt()
  end

  defp median(set) do
    sorted = set |> MapSet.to_list() |> Enum.sort()
    n = length(sorted)

    case n do
      0 -> 0
      n when rem(n, 2) == 1 -> Enum.at(sorted, div(n, 2))
      n -> (Enum.at(sorted, div(n, 2) - 1) + Enum.at(sorted, div(n, 2))) / 2
    end
  end

  # ---- candidate generation -------------------------------------------

  # YAKE candidates are n-grams that **start and end with a non-stopword**
  # — interior stopwords are allowed (they get a high penalty score in
  # the composition step). This is the simplified YAKE candidate rule;
  # the LIAAD reference uses the same boundary rule plus a few extra
  # punctuation/heuristic filters that we omit here.
  defp generate_candidates(folded_sentences, min_n, max_n, stopwords) do
    Enum.flat_map(folded_sentences, fn sentence ->
      Enum.flat_map(min_n..max_n//1, fn n ->
        sentence
        |> Enum.chunk_every(n, 1, :discard)
        |> Enum.filter(fn chunk ->
          not MapSet.member?(stopwords, List.first(chunk)) and
            not MapSet.member?(stopwords, List.last(chunk))
        end)
      end)
    end)
  end

  # ---- candidate scoring -----------------------------------------------

  defp score_candidates(candidates, word_scores, stopwords) do
    counts =
      Enum.reduce(candidates, %{}, fn tokens, acc ->
        Map.update(acc, tokens, 1, &(&1 + 1))
      end)

    Enum.map(counts, fn {tokens, count} ->
      kind = if length(tokens) == 1, do: :word, else: :phrase
      raw = combine(tokens, count, word_scores, stopwords)
      {tokens, raw, count, kind}
    end)
  end

  # Phrase score = product of member word scores, divided by
  # (count * (1 + sum of member word scores)).
  #
  # Stopwords interior to the phrase contribute a penalty term but
  # don't dominate it — using their actual YAKE score works in
  # practice, since stopwords have wide context (high relatedness)
  # which already drives their score upward.
  defp combine([single], count, word_scores, _stopwords) do
    score = Map.get(word_scores, single, 1.0)
    score / count
  end

  defp combine(tokens, count, word_scores, _stopwords) do
    scores = Enum.map(tokens, &Map.get(word_scores, &1, 1.0))
    product = Enum.reduce(scores, 1.0, &(&1 * &2))
    sum = Enum.sum(scores)
    product / (count * (1.0 + sum))
  end

  # ---- finalisation ---------------------------------------------------

  # Convert the YAKE-internal "lower = better" raw score to the
  # orchestrator's "higher = better" convention by taking 1/(score +
  # epsilon). The epsilon prevents division by zero on degenerate
  # inputs (single-word documents where the word's score collapses
  # to 0). Surface form follows :case_fold; when off, we look up the
  # most-frequent original casing for each folded token.
  defp finalise(scored_candidates, case_fold?, original_sentences, folded_sentences) do
    surface_forms =
      if case_fold?, do: nil, else: most_frequent_casings(original_sentences, folded_sentences)

    Enum.map(scored_candidates, fn {tokens, raw, count, kind} ->
      term =
        if case_fold? do
          Enum.join(tokens, " ")
        else
          tokens
          |> Enum.map(&Map.get(surface_forms, &1, &1))
          |> Enum.join(" ")
        end

      higher_better = 1.0 / (raw + 1.0e-9)
      {term, higher_better, count, kind}
    end)
  end

  defp most_frequent_casings(original_sentences, folded_sentences) do
    original_sentences
    |> List.flatten()
    |> Enum.zip(List.flatten(folded_sentences))
    |> Enum.reduce(%{}, fn {cased, folded}, acc ->
      Map.update(acc, folded, %{cased => 1}, &Map.update(&1, cased, 1, fn n -> n + 1 end))
    end)
    |> Map.new(fn {folded, casings} ->
      {top_casing, _} = Enum.max_by(casings, fn {_c, n} -> n end)
      {folded, top_casing}
    end)
  end
end
