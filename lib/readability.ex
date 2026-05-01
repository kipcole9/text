defmodule Text.Readability do
  @moduledoc """
  Readability metrics for English text.

  Implements the classic readability indices used to estimate the
  reading difficulty of a passage:

  * `flesch/2` — Flesch Reading Ease (higher = easier).
  * `flesch_kincaid/2` — Flesch-Kincaid Grade Level (US school grade).
  * `gunning_fog/2` — Gunning-Fog Index (years of education).
  * `smog/2` — SMOG Index (years of education; needs ~30 sentences).
  * `ari/2` — Automated Readability Index (US school grade).
  * `coleman_liau/2` — Coleman-Liau Index (US school grade).
  * `lix/2` — LIX (Läsbarhetsindex; language-agnostic-ish).
  * `dale_chall/2` — Dale-Chall (US school grade); uses the bundled
    ~3,000-word easy-words list.
  * `spache/2` — Spache (US school grade, K-3 readers); uses the
    bundled ~1,000-word easy-words list.

  Use `metrics/2` to compute every index in one pass over the text,
  and `statistics/2` to inspect the raw counts (words, sentences,
  syllables, characters, polysyllables, long words) the metrics are
  built from.

  Sentence and word segmentation use `Text.Segment` (UAX #29 with
  CLDR abbreviation suppressions). Syllable counting uses
  `Text.Syllable`, which currently supports English only — so all
  metrics that depend on syllable counts (Flesch, Flesch-Kincaid,
  Gunning-Fog, SMOG) are English-only. ARI, Coleman-Liau, and LIX
  are character/length-based and work for any whitespace-segmented
  language. Dale-Chall and Spache are English-only and use the
  bundled easy-word lists in `priv/readability/`.

  """

  alias Text.Segment
  alias Text.Syllable

  @dale_chall_path "priv/readability/dale_chall.txt"
  @spache_path "priv/readability/spache.txt"
  @external_resource @dale_chall_path
  @external_resource @spache_path

  @dale_chall_words @dale_chall_path
                    |> File.read!()
                    |> String.split(~r/\r?\n/, trim: true)
                    |> Enum.map(&String.downcase/1)
                    |> MapSet.new()

  @spache_words @spache_path
                |> File.read!()
                |> String.split(~r/\r?\n/, trim: true)
                |> Enum.map(&String.downcase/1)
                |> MapSet.new()

  @typedoc "Raw text statistics used to compute the readability metrics."
  @type statistics :: %{
          characters: non_neg_integer(),
          letters: non_neg_integer(),
          words: non_neg_integer(),
          sentences: non_neg_integer(),
          syllables: non_neg_integer(),
          polysyllables: non_neg_integer(),
          long_words: non_neg_integer(),
          difficult_words: non_neg_integer(),
          unfamiliar_words: non_neg_integer(),
          average_sentence_length: float(),
          average_syllables_per_word: float()
        }

  @typedoc "Map of every readability metric computed for a text."
  @type metrics :: %{
          flesch: float(),
          flesch_kincaid: float(),
          gunning_fog: float(),
          smog: float(),
          ari: float(),
          coleman_liau: float(),
          lix: float(),
          dale_chall: float(),
          spache: float()
        }

  @long_word_threshold 7
  @polysyllable_threshold 3

  @doc """
  Returns the raw text statistics used by the readability metrics.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the language used for syllable counting and
    sentence segmentation. The default is `:en`. Only `:en` is
    supported by the syllable counter today.

  ### Returns

  * A map with the keys `:characters`, `:letters`, `:words`,
    `:sentences`, `:syllables`, `:polysyllables`, `:long_words`,
    `:average_sentence_length`, and `:average_syllables_per_word`.
    Empty input returns zeroed counts and `0.0` averages.

  ### Examples

      iex> stats = Text.Readability.statistics("The cat sat on the mat. The dog ran.")
      iex> stats.words
      9
      iex> stats.sentences
      2

  """
  @spec statistics(String.t(), keyword()) :: statistics()
  def statistics(text, options \\ []) when is_binary(text) do
    language = Keyword.get(options, :language, :en)

    sentences = Segment.sentences(text, locale: to_string(language))
    sentence_count = length(sentences)

    words = Segment.words(text, locale: to_string(language))
    word_count = length(words)

    {syllables, polysyllables, long_words, letters, difficult, unfamiliar} =
      Enum.reduce(words, {0, 0, 0, 0, 0, 0}, fn word, {sy, poly, long, letters, dc, sp} ->
        s = Syllable.count(word, language: language)
        l = letters_in(word)
        word_lower = String.downcase(word)
        word_len = String.length(word)

        {
          sy + s,
          poly + if(s >= @polysyllable_threshold, do: 1, else: 0),
          long + if(word_len >= @long_word_threshold, do: 1, else: 0),
          letters + l,
          dc + if(letter_word?(word) and not MapSet.member?(@dale_chall_words, word_lower), do: 1, else: 0),
          sp + if(letter_word?(word) and not MapSet.member?(@spache_words, word_lower), do: 1, else: 0)
        }
      end)

    %{
      characters: String.length(text),
      letters: letters,
      words: word_count,
      sentences: sentence_count,
      syllables: syllables,
      polysyllables: polysyllables,
      long_words: long_words,
      difficult_words: difficult,
      unfamiliar_words: unfamiliar,
      average_sentence_length: safe_div(word_count, sentence_count),
      average_syllables_per_word: safe_div(syllables, word_count)
    }
  end

  @doc """
  Returns the Flesch Reading Ease score.

  Higher scores mean easier text. 60-70 is "plain English"; 30-50
  is "difficult"; 0-30 is "very confusing".

  Formula: `206.835 − 1.015 × (words/sentences) − 84.6 × (syllables/words)`.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the syllable-counting language, default `:en`.

  ### Returns

  * A float. Returns `0.0` if the text has no sentences or words.

  ### Examples

      iex> Text.Readability.flesch("The cat sat on the mat.") |> Float.round(1)
      116.1

  """
  @spec flesch(String.t() | statistics(), keyword()) :: float()
  def flesch(text_or_stats, options \\ [])
  def flesch(text, options) when is_binary(text), do: flesch(statistics(text, options), options)

  def flesch(%{words: 0}, _options), do: 0.0
  def flesch(%{sentences: 0}, _options), do: 0.0

  def flesch(%{average_sentence_length: asl, average_syllables_per_word: aspw}, _options) do
    206.835 - 1.015 * asl - 84.6 * aspw
  end

  @doc """
  Returns the Flesch-Kincaid Grade Level.

  Output is a US school grade level (e.g. `8.5` ≈ mid eighth grade).

  Formula: `0.39 × (words/sentences) + 11.8 × (syllables/words) − 15.59`.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the syllable-counting language, default `:en`.

  ### Returns

  * A float grade level. Returns `0.0` for empty input.

  ### Examples

      iex> Text.Readability.flesch_kincaid("The cat sat on the mat.") |> Float.round(1)
      -1.4

  """
  @spec flesch_kincaid(String.t() | statistics(), keyword()) :: float()
  def flesch_kincaid(text_or_stats, options \\ [])

  def flesch_kincaid(text, options) when is_binary(text),
    do: flesch_kincaid(statistics(text, options), options)

  def flesch_kincaid(%{words: 0}, _options), do: 0.0
  def flesch_kincaid(%{sentences: 0}, _options), do: 0.0

  def flesch_kincaid(%{average_sentence_length: asl, average_syllables_per_word: aspw}, _options) do
    0.39 * asl + 11.8 * aspw - 15.59
  end

  @doc """
  Returns the Gunning-Fog Index.

  Output is roughly the years of formal education a reader needs.
  12 is a US high-school senior; 17+ is graduate-level.

  Formula: `0.4 × ((words/sentences) + 100 × (complex_words/words))`,
  where a complex word is one with 3 or more syllables.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the syllable-counting language, default `:en`.

  ### Returns

  * A float. Returns `0.0` for empty input.

  ### Examples

      iex> Text.Readability.gunning_fog("The complicated explanation confused everyone immediately.") |> Float.round(1)
      35.7

  """
  @spec gunning_fog(String.t() | statistics(), keyword()) :: float()
  def gunning_fog(text_or_stats, options \\ [])

  def gunning_fog(text, options) when is_binary(text),
    do: gunning_fog(statistics(text, options), options)

  def gunning_fog(%{words: 0}, _options), do: 0.0
  def gunning_fog(%{sentences: 0}, _options), do: 0.0

  def gunning_fog(%{words: words, sentences: sentences, polysyllables: complex}, _options) do
    0.4 * (words / sentences + 100 * complex / words)
  end

  @doc """
  Returns the SMOG Index (Simple Measure Of Gobbledygook).

  Output is roughly the years of formal education a reader needs.
  Designed to be applied to passages of about 30 sentences; results
  on shorter passages are less reliable.

  Formula: `1.0430 × √(polysyllables × 30 / sentences) + 3.1291`.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the syllable-counting language, default `:en`.

  ### Returns

  * A float. Returns `0.0` for empty input.

  ### Examples

      iex> Text.Readability.smog("The cat sat on the mat. The dog ran fast.") |> is_float()
      true

  """
  @spec smog(String.t() | statistics(), keyword()) :: float()
  def smog(text_or_stats, options \\ [])

  def smog(text, options) when is_binary(text), do: smog(statistics(text, options), options)
  def smog(%{sentences: 0}, _options), do: 0.0

  def smog(%{polysyllables: poly, sentences: sentences}, _options) do
    1.0430 * :math.sqrt(poly * 30 / sentences) + 3.1291
  end

  @doc """
  Returns the Automated Readability Index.

  Output is a US school grade level. Character-based rather than
  syllable-based, so it works for any whitespace-segmented language.

  Formula: `4.71 × (letters/words) + 0.5 × (words/sentences) − 21.43`.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the segmentation locale, default `:en`.

  ### Returns

  * A float grade level. Returns `0.0` for empty input.

  ### Examples

      iex> Text.Readability.ari("The cat sat on the mat.") |> Float.round(1)
      -5.1

  """
  @spec ari(String.t() | statistics(), keyword()) :: float()
  def ari(text_or_stats, options \\ [])
  def ari(text, options) when is_binary(text), do: ari(statistics(text, options), options)
  def ari(%{words: 0}, _options), do: 0.0
  def ari(%{sentences: 0}, _options), do: 0.0

  def ari(%{letters: letters, words: words, sentences: sentences}, _options) do
    4.71 * (letters / words) + 0.5 * (words / sentences) - 21.43
  end

  @doc """
  Returns the Coleman-Liau Index.

  Output is a US school grade level. Character-based; no syllable
  counting required.

  Formula: `0.0588 × L − 0.296 × S − 15.8`, where `L` is letters
  per 100 words and `S` is sentences per 100 words.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the segmentation locale, default `:en`.

  ### Returns

  * A float grade level. Returns `0.0` for empty input.

  ### Examples

      iex> Text.Readability.coleman_liau("The cat sat on the mat.") |> Float.round(1)
      -4.1

  """
  @spec coleman_liau(String.t() | statistics(), keyword()) :: float()
  def coleman_liau(text_or_stats, options \\ [])

  def coleman_liau(text, options) when is_binary(text),
    do: coleman_liau(statistics(text, options), options)

  def coleman_liau(%{words: 0}, _options), do: 0.0

  def coleman_liau(%{letters: letters, words: words, sentences: sentences}, _options) do
    l = letters * 100 / words
    s = sentences * 100 / words
    0.0588 * l - 0.296 * s - 15.8
  end

  @doc """
  Returns the LIX (Läsbarhetsindex) readability score.

  Designed for Swedish but used as a language-agnostic indicator.
  A long word is one with 7 or more characters.

  Formula: `(words/sentences) + 100 × (long_words/words)`.

  Interpretation: <30 very easy, 30-40 easy, 40-50 medium,
  50-60 difficult, >60 very difficult.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the segmentation locale, default `:en`.

  ### Returns

  * A float. Returns `0.0` for empty input.

  ### Examples

      iex> Text.Readability.lix("The cat sat on the mat.") |> Float.round(1)
      6.0

  """
  @spec lix(String.t() | statistics(), keyword()) :: float()
  def lix(text_or_stats, options \\ [])
  def lix(text, options) when is_binary(text), do: lix(statistics(text, options), options)
  def lix(%{words: 0}, _options), do: 0.0
  def lix(%{sentences: 0}, _options), do: 0.0

  def lix(%{words: words, sentences: sentences, long_words: long}, _options) do
    words / sentences + 100 * long / words
  end

  @doc """
  Returns the Dale-Chall readability score.

  Output is a US school grade level. Computed from the percentage of
  *difficult* words — words **not** in the bundled ~3,000-word
  easy-words list — and the average sentence length. Uses the
  Chall-Dale 1995 adjustment: the raw score is shifted by `+3.6365`
  when more than 5% of words are difficult.

  Formula: `0.1579 × (PDW × 100) + 0.0496 × ASL [+ 3.6365 if PDW > 0.05]`,
  where `PDW` is the proportion of difficult words and `ASL` is
  average sentence length.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the segmentation locale, default `:en`. The
    bundled easy-words list is English-only.

  ### Returns

  * A float grade level. Returns `0.0` for empty input.

  ### Examples

      iex> Text.Readability.dale_chall("The cat sat on the mat.") |> is_float()
      true

  """
  @spec dale_chall(String.t() | statistics(), keyword()) :: float()
  def dale_chall(text_or_stats, options \\ [])

  def dale_chall(text, options) when is_binary(text),
    do: dale_chall(statistics(text, options), options)

  def dale_chall(%{words: 0}, _options), do: 0.0
  def dale_chall(%{sentences: 0}, _options), do: 0.0

  def dale_chall(%{words: words, sentences: sentences, difficult_words: difficult}, _options) do
    pdw = difficult / words
    asl = words / sentences
    raw = 0.1579 * (pdw * 100) + 0.0496 * asl
    if pdw > 0.05, do: raw + 3.6365, else: raw
  end

  @doc """
  Returns the Spache readability score.

  Output is a US school grade level, intended for K-3 reading
  material. Computed from the percentage of *unfamiliar* words —
  words **not** in the bundled ~1,000-word Spache easy-words list —
  and average sentence length.

  Formula: `0.121 × ASL + 0.082 × (UPW × 100) + 0.659`, where `ASL`
  is average sentence length and `UPW` is the proportion of
  unfamiliar words.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the segmentation locale, default `:en`. The
    bundled easy-words list is English-only.

  ### Returns

  * A float grade level. Returns `0.0` for empty input.

  ### Examples

      iex> Text.Readability.spache("The cat sat on the mat.") |> is_float()
      true

  """
  @spec spache(String.t() | statistics(), keyword()) :: float()
  def spache(text_or_stats, options \\ [])

  def spache(text, options) when is_binary(text),
    do: spache(statistics(text, options), options)

  def spache(%{words: 0}, _options), do: 0.0
  def spache(%{sentences: 0}, _options), do: 0.0

  def spache(%{words: words, sentences: sentences, unfamiliar_words: unfamiliar}, _options) do
    asl = words / sentences
    upw = unfamiliar / words * 100
    0.121 * asl + 0.082 * upw + 0.659
  end

  @doc """
  Computes every readability metric in one pass.

  ### Arguments

  * `text` is a string of one or more sentences.

  ### Options

  * `:language` is the syllable-counting and segmentation language,
    default `:en`.

  ### Returns

  * A map with the keys `:flesch`, `:flesch_kincaid`, `:gunning_fog`,
    `:smog`, `:ari`, `:coleman_liau`, `:lix`, `:dale_chall`, and
    `:spache`. Empty input yields `0.0` for every metric.

  ### Examples

      iex> Text.Readability.metrics("The cat sat on the mat.") |> Map.keys() |> Enum.sort()
      [:ari, :coleman_liau, :dale_chall, :flesch, :flesch_kincaid, :gunning_fog, :lix, :smog, :spache]

  """
  @spec metrics(String.t(), keyword()) :: metrics()
  def metrics(text, options \\ []) when is_binary(text) do
    stats = statistics(text, options)

    %{
      flesch: flesch(stats, options),
      flesch_kincaid: flesch_kincaid(stats, options),
      gunning_fog: gunning_fog(stats, options),
      smog: smog(stats, options),
      ari: ari(stats, options),
      coleman_liau: coleman_liau(stats, options),
      lix: lix(stats, options),
      dale_chall: dale_chall(stats, options),
      spache: spache(stats, options)
    }
  end

  defp letters_in(word) do
    word
    |> String.to_charlist()
    |> Enum.count(&letter?/1)
  end

  defp letter?(c) when c >= ?a and c <= ?z, do: true
  defp letter?(c) when c >= ?A and c <= ?Z, do: true
  defp letter?(_), do: false

  # Treat tokens with at least one letter as candidates for the
  # easy/difficult check; pure punctuation and digit tokens shouldn't
  # count as "difficult" simply because they're not in the lexicon.
  defp letter_word?(word) do
    word
    |> String.to_charlist()
    |> Enum.any?(&letter?/1)
  end

  defp safe_div(_numerator, 0), do: 0.0
  defp safe_div(numerator, denominator), do: numerator / denominator
end
