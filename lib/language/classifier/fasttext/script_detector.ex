defmodule Text.Language.Classifier.Fasttext.ScriptDetector do
  @moduledoc """
  Identifies the dominant Unicode script of a piece of text.

  fastText's `lid.176` classifier reports a language code (e.g. `zh`,
  `sr`) without distinguishing scripts: Chinese is `zh` whether the input
  is Simplified or Traditional Han, Serbian is `sr` whether written in
  Latin or Cyrillic. The script signal is needed downstream to assemble a
  full CLDR locale (e.g. `zh-Hans-CN` vs `zh-Hant-TW`).

  This module is a thin wrapper around `Unicode.script_dominance/1` from
  the [`unicode`](https://hex.pm/packages/unicode) Hex package. The
  wrapper does two things:

  * Returns the most-frequent script as a single ISO 15924 four-letter
    atom (`:Latn`, `:Cyrl`, `:Hans`, ...) suitable for direct use in
    BCP-47 locale strings.

  * Folds Unicode's `:common` script (digits, punctuation, whitespace —
    "characters used in many scripts") out of the dominance computation,
    so a sentence with one Cyrillic word and three trailing punctuation
    marks still resolves to `:Cyrl`.

  ### Han disambiguation

  `Unicode.script_dominance/1` reports CJK ideographs as `:han`. When
  the dominant script of the input is Han, `detect/1` runs a second
  pass over the codepoints comparing them against curated lists of
  Simplified-only (`Hans`) and Traditional-only (`Hant`) characters.
  The variant whose count is higher wins; ties (including text using
  only shared Han codepoints) fall back to the generic `:Hani`.

  The curated lists cover the ~50 most distinguishing characters for
  each variant — the high-frequency function words and pronouns that
  reliably differ between Simplified and Traditional. They are not
  exhaustive (the [Unihan
  Variants](https://www.unicode.org/reports/tr38/) database has
  thousands of entries) but cover the realistic case where the input
  is more than a handful of characters long. For shorter or
  ambiguous input, the disambiguation may stay at `:Hani`.

  """

  # Mapping from `Unicode` package script atoms (lowercase, descriptive)
  # to ISO 15924 four-letter codes used by BCP-47 / CLDR. Only the scripts
  # `lid.176` actually emits language tags for are listed.
  @iso_15924 %{
    latin: :Latn,
    cyrillic: :Cyrl,
    greek: :Grek,
    arabic: :Arab,
    hebrew: :Hebr,
    devanagari: :Deva,
    bengali: :Beng,
    tamil: :Taml,
    telugu: :Telu,
    gujarati: :Gujr,
    gurmukhi: :Guru,
    kannada: :Knda,
    malayalam: :Mlym,
    sinhala: :Sinh,
    oriya: :Orya,
    thai: :Thai,
    lao: :Laoo,
    myanmar: :Mymr,
    khmer: :Khmr,
    georgian: :Geor,
    armenian: :Armn,
    han: :Hani,
    hiragana: :Hira,
    katakana: :Kana,
    hangul: :Hang,
    ethiopic: :Ethi,
    tibetan: :Tibt,
    mongolian: :Mong
  }

  @type script :: atom()

  # Codepoints that exist *only* in Simplified Chinese: their
  # Traditional equivalents have different codepoints (`国` ↔ `國`,
  # `学` ↔ `學`, …). Curated from the most common ~60 distinguishing
  # function words, pronouns, common verbs, and high-frequency nouns.
  @hans_only_codepoints MapSet.new(
                          ~c"国学时来这个们与为经后还没现实当处应让总极区选议队体点开关龙华爱进发业东车报边长万门问间听说样头觉见画书认识语话读写传专属赞议价较脑亲笔诉觉养"
                        )

  # Codepoints that exist *only* in Traditional Chinese.
  @hant_only_codepoints MapSet.new(
                          ~c"國學時來這個們與為經後還沒現實當處應讓總極區選議隊體點開關龍華愛進發業東車報邊長萬門問間聽說樣頭覺見畫書認識語話讀寫傳專屬贊議價較腦親筆訴覺養"
                        )

  @doc """
  Returns the dominant script of `text` as an ISO 15924 four-letter atom.

  ### Arguments

  * `text` is a UTF-8 binary.

  ### Returns

  * An ISO 15924 four-letter script code (e.g. `:Latn`, `:Cyrl`, `:Hani`,
    `:Hira`, `:Hang`).

  * `:Zyyy` (the ISO 15924 "common" sentinel) when the input is empty or
    contains only digits, punctuation, and other non-script characters.

  ### Examples

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.detect("Hello world")
      :Latn

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.detect("Привет мир")
      :Cyrl

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.detect("你好世界，这是中文")
      :Hans

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.detect("你好世界，這是中文")
      :Hant

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.detect("你好世界")
      :Hani

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.detect("こんにちは")
      :Hira

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.detect("123 !!!")
      :Zyyy

  """
  @spec detect(binary()) :: script()
  def detect(text) when is_binary(text) do
    # `Unicode.script_dominance/1` lists scripts in order of first
    # appearance, not by frequency, so a sentence like "hi мир там"
    # would resolve to Latin if we just took the head. Sort by count
    # descending to actually pick the dominant script.
    iso =
      text
      |> Unicode.script_dominance()
      |> Enum.reject(fn {script, _} -> script == :common end)
      |> Enum.max_by(fn {_script, {_first_pos, count}} -> count end, fn -> nil end)
      |> case do
        nil -> :Zyyy
        {script, _} -> Map.get(@iso_15924, script, :Zzzz)
      end

    # Run the second-pass Hans/Hant disambiguation only when the
    # primary detection settled on generic Han.
    case iso do
      :Hani -> han_variant(text)
      other -> other
    end
  end

  @doc """
  Returns the Han variant (`:Hans`, `:Hant`, or `:Hani`) for the
  Han-script content of `text`.

  Counts codepoints against curated lists of Simplified-only and
  Traditional-only characters. The variant with the higher count
  wins; ties (or text containing only codepoints shared between the
  variants) return `:Hani`.

  Useful when the caller already knows the script is Han (for
  instance, after running `detect/1` and seeing `:Hani`) and wants
  the variant separately. `detect/1` calls this internally.

  ### Examples

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.han_variant("国学时来这")
      :Hans

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.han_variant("國學時來這")
      :Hant

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.han_variant("你好世界")
      :Hani

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.han_variant("Hello world")
      :Hani

  """
  @spec han_variant(binary()) :: :Hans | :Hant | :Hani
  def han_variant(text) when is_binary(text) do
    {hans, hant} =
      text
      |> :unicode.characters_to_list(:utf8)
      |> Enum.reduce({0, 0}, fn cp, {hans, hant} ->
        cond do
          MapSet.member?(@hans_only_codepoints, cp) -> {hans + 1, hant}
          MapSet.member?(@hant_only_codepoints, cp) -> {hans, hant + 1}
          true -> {hans, hant}
        end
      end)

    cond do
      hans > hant -> :Hans
      hant > hans -> :Hant
      true -> :Hani
    end
  end

  @doc """
  Returns the per-script codepoint counts as a map keyed by ISO 15924
  atoms.

  Useful when a caller needs more than the dominant script — e.g. a
  mixed-script input may want a confidence ratio across scripts.

  ### Examples

      iex> Text.Language.Classifier.Fasttext.ScriptDetector.tally("Hello мир")
      %{Latn: 5, Cyrl: 3}

  """
  @spec tally(binary()) :: %{script() => non_neg_integer()}
  def tally(text) when is_binary(text) do
    text
    |> Unicode.script_statistic()
    |> Enum.reduce(%{}, fn
      {:common, _}, acc ->
        acc

      {unicode_script, {_first_pos, count}}, acc ->
        iso = Map.get(@iso_15924, unicode_script, :Zzzz)
        Map.update(acc, iso, count, &(&1 + count))
    end)
  end
end
