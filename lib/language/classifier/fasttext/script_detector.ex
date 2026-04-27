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

  `Unicode.script_dominance/1` reports CJK ideographs as `:han`. This
  module maps that to `:Hani` — the ISO 15924 generic Han code. The
  Hans/Hant choice (Simplified vs Traditional) is left to
  `Text.Language.Classifier.Fasttext.Locale`, which combines the script
  signal with the detected language and any region hint.

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
    text
    |> Unicode.script_dominance()
    |> Enum.reject(fn {script, _} -> script == :common end)
    |> Enum.max_by(fn {_script, {_first_pos, count}} -> count end, fn -> nil end)
    |> case do
      nil -> :Zyyy
      {script, _} -> Map.get(@iso_15924, script, :Zzzz)
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
