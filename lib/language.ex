defmodule Text.Language do
  @moduledoc """
  Language tag utilities used across the package.

  Every function in `text` that takes a "language" option accepts:

  * an atom (`:fr`, `:zh`),

  * a string (`"fr"`, `"fr-CA"`, `"zh-Hans-CN"`),

  * or a `Localize.LanguageTag` struct, when the optional
    [`localize`](https://hex.pm/packages/localize) dependency is
    available.

  This module provides the normalisation helpers that unify those
  shapes so the call sites remain simple.

  ### `normalize/1` — to a language-subtag atom

  Most internal lookups (sentiment lexicons, classifier outputs, …)
  key on the bare ISO 639-1 language subtag. `normalize/1` extracts
  that subtag from any of the accepted shapes:

      iex> Text.Language.normalize(:fr)
      :fr

      iex> Text.Language.normalize("fr-CA")
      :fr

      iex> Text.Language.normalize("ZH-Hans-CN")
      :zh

  ### `to_locale_string/1` — to a BCP-47 string

  Some downstream APIs (CLDR-aware tokenisation, locale-aware
  formatting) want the full BCP-47 form. `to_locale_string/1` produces
  a normalised string suitable for passing to `unicode_string`,
  `localize`, etc.

      iex> Text.Language.to_locale_string(:fr)
      "fr"

      iex> Text.Language.to_locale_string("fr_CA")
      "fr-CA"

  """

  @typedoc """
  Anything `normalize/1` and `to_locale_string/1` accept.

  When `:localize` is available, also includes `Localize.LanguageTag`
  structs.
  """
  @type input :: atom() | String.t() | struct()

  @doc """
  Returns the language subtag of `input` as a lowercase atom.

  ### Arguments

  * `input` is one of the accepted shapes — atom, string, or (when
    `:localize` is loaded) a `Localize.LanguageTag` struct.

  ### Returns

  * An atom — the language subtag of the input (e.g. `:fr` for
    `"fr-CA"` or a `LanguageTag` whose language is `:fr`).

  ### Examples

      iex> Text.Language.normalize(:fr)
      :fr

      iex> Text.Language.normalize("fr-CA")
      :fr

      iex> Text.Language.normalize("FR")
      :fr

  """
  @spec normalize(input()) :: atom()
  def normalize(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> language_subtag_from_string()
    |> String.to_atom()
  end

  def normalize(string) when is_binary(string) do
    string
    |> language_subtag_from_string()
    |> String.to_atom()
  end

  if Code.ensure_loaded?(Localize.LanguageTag) do
    def normalize(%Localize.LanguageTag{language: language})
        when is_atom(language) and not is_nil(language) do
      language
    end
  end

  @doc """
  Returns a normalised BCP-47 locale string for `input`.

  Splits on `_` (Java-style separator) as well as `-` and joins the
  subtags with `-`. The language subtag is lowercased; subsequent
  subtags are passed through unchanged. For a `Localize.LanguageTag`
  the canonical id is used when present, otherwise the
  language/script/territory triple is composed.

  ### Arguments

  * `input` is one of the accepted shapes.

  ### Returns

  * A `t:String.t/0`.

  ### Examples

      iex> Text.Language.to_locale_string(:fr)
      "fr"

      iex> Text.Language.to_locale_string("fr_CA")
      "fr-CA"

      iex> Text.Language.to_locale_string("ZH-Hans-CN")
      "zh-Hans-CN"

  """
  @spec to_locale_string(input()) :: String.t()
  def to_locale_string(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> normalize_locale_string()
  end

  def to_locale_string(string) when is_binary(string) do
    normalize_locale_string(string)
  end

  if Code.ensure_loaded?(Localize.LanguageTag) do
    def to_locale_string(%Localize.LanguageTag{canonical_locale_id: id})
        when is_binary(id) and id != "" do
      normalize_locale_string(id)
    end

    def to_locale_string(%Localize.LanguageTag{language: lang} = tag)
        when is_atom(lang) and not is_nil(lang) do
      [tag.language, tag.script, tag.territory]
      |> Enum.reject(&(&1 in [nil, :"", ""]))
      |> Enum.map(&to_string/1)
      |> Enum.join("-")
      |> normalize_locale_string()
    end
  end

  # ---- internal ---------------------------------------------------------

  defp language_subtag_from_string(string) do
    string
    |> String.split(~r/[-_]/)
    |> hd()
    |> String.downcase()
  end

  defp normalize_locale_string(string) do
    string
    |> String.split(~r/[-_]/)
    |> case do
      [] ->
        ""

      [language | rest] ->
        [String.downcase(language) | rest]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("-")
    end
  end
end
