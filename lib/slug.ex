defmodule Text.Slug do
  @moduledoc """
  URL-safe slug generation with locale-aware Unicode folding.

  Produces a lowercase, separator-joined ASCII string suitable for URLs,
  filenames, and other identifiers from any UTF-8 input. Unlike a naive
  ASCII filter, this module handles:

  * **Latin diacritics** — `"café résumé"` → `"cafe-resume"`.

  * **Locale-specific folding rules** baked into CLDR — German `"ß"`
    folds to `"ss"`, Turkish `"İ"` to `"i"`, Vietnamese `"Đ"` to `"D"`,
    etc. (via the
    [`unicode_transform`](https://hex.pm/packages/unicode_transform)
    package's `Latin-ASCII` transform).

  * **Cross-script transliteration** — `"Привет мир"` → `"privet-mir"`,
    `"北京"` → `"beijing"`, `"こんにちは"` → `"konnichiha"` — for inputs
    in any script `unicode_transform` has a `<Script>-Latin` transform
    for. Disable with `transliterate: false` to drop non-Latin characters
    instead.

  ### Algorithm

  1. (Optional) per-script transliteration via `unicode_transform`,
     leaving Latin runs untouched.

  2. ASCII folding via `Latin-ASCII` (handles diacritics and the
     locale-specific cases above).

  3. Lowercase.

  4. Replace each maximal run of non-`[a-z0-9]` characters with the
     separator.

  5. Trim leading and trailing separators.

  """

  @default_separator "-"

  @doc """
  Returns a URL-safe slug for the given string.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Options

  * `:separator` — the joining string used between word runs and
    inserted in place of non-alphanumeric characters. Defaults to
    `"-"`. Any non-empty string is allowed; `"_"` is the common
    alternative.

  * `:transliterate` — when `true` (default), characters in non-Latin
    scripts are first transliterated to Latin via `unicode_transform`'s
    `<Script>-Latin` transforms (for those scripts that have one).
    When `false`, non-Latin characters are dropped during the ASCII
    folding step.

  ### Returns

  * A non-empty lowercase ASCII string. Returns `""` if the input has
    no characters that survive the pipeline (e.g. all-emoji input
    with `transliterate: false`).

  ### Examples

      iex> Text.Slug.slugify("Hello World")
      "hello-world"

      iex> Text.Slug.slugify("café résumé")
      "cafe-resume"

      iex> Text.Slug.slugify("Straße München")
      "strasse-munchen"

      iex> Text.Slug.slugify("İstanbul Çanakkale")
      "istanbul-canakkale"

      iex> Text.Slug.slugify("Đà Nẵng")
      "da-nang"

      iex> Text.Slug.slugify("Hello World", separator: "_")
      "hello_world"

      iex> Text.Slug.slugify("  multiple   spaces  ")
      "multiple-spaces"

      iex> Text.Slug.slugify("a/b\\\\c")
      "a-b-c"

  """
  @spec slugify(String.t(), keyword()) :: String.t()
  def slugify(text, options \\ []) when is_binary(text) do
    separator = Keyword.get(options, :separator, @default_separator)
    transliterate? = Keyword.get(options, :transliterate, true)

    text
    |> maybe_transliterate(transliterate?)
    |> ascii_fold()
    |> String.downcase()
    |> replace_non_word(separator)
    |> trim_separator(separator)
  end

  # ---- transliteration ---------------------------------------------------

  defp maybe_transliterate(text, false) do
    # When transliteration is off, drop characters whose script the
    # `Latin-ASCII` transform doesn't know how to fold. Without this,
    # mixed-script inputs leak Latin letters through the non-word
    # replace step (e.g. `"café 北京"` would lose the `é` because the
    # fold can't run on the trailing Han ideographs).
    text
    |> :unicode.characters_to_list(:utf8)
    |> Enum.filter(fn cp ->
      script = codepoint_script(cp)
      script in [:latin, :common, :inherited]
    end)
    |> List.to_string()
  end

  defp maybe_transliterate(text, true) do
    case Unicode.Transform.transform(text, transform: "Any-Latin") do
      {:ok, result} ->
        result

      {:error, {:unknown_transform, "Latin-Latin"}} ->
        # The string contains Latin runs alongside other scripts;
        # `Any-Latin` doesn't define a Latin → Latin no-op. Fall back
        # to per-script handling.
        transliterate_per_script(text)

      {:error, _} ->
        text
    end
  end

  defp transliterate_per_script(text) do
    text
    |> :unicode.characters_to_list(:utf8)
    |> Enum.chunk_by(&codepoint_script/1)
    |> Enum.map(&transliterate_run/1)
    |> Enum.join()
  end

  defp transliterate_run(codepoints) do
    script = codepoints |> hd() |> codepoint_script()
    string = List.to_string(codepoints)

    cond do
      script in [:latin, :common, :inherited, :unknown] ->
        string

      true ->
        transform_id = script_to_transform_id(script)

        case Unicode.Transform.transform(string, transform: transform_id) do
          {:ok, result} -> result
          _ -> string
        end
    end
  end

  defp codepoint_script(codepoint) when is_integer(codepoint) do
    case Unicode.script(codepoint) do
      atom when is_atom(atom) -> atom
      _ -> :unknown
    end
  end

  # The `unicode` package returns lowercase atoms (`:cyrillic`, `:han`,
  # `:hiragana`, ...) and `unicode_transform` uses capitalised IDs
  # (`Cyrillic-Latin`, `Han-Latin`, ...). The simple capitalisation
  # works for every script in `unicode_transform`'s catalogue except
  # the multi-word `:canadian_aboriginal`, handled explicitly.
  defp script_to_transform_id(:canadian_aboriginal), do: "CanadianAboriginal-Latin"

  defp script_to_transform_id(script) do
    name =
      script
      |> Atom.to_string()
      |> String.capitalize()

    name <> "-Latin"
  end

  # ---- ASCII folding -----------------------------------------------------

  defp ascii_fold(text) do
    case Unicode.Transform.transform(text, to: "ASCII") do
      {:ok, result} -> result
      _ -> text
    end
  end

  # ---- separator handling -----------------------------------------------

  defp replace_non_word(text, separator) do
    Regex.replace(~r/[^a-z0-9]+/u, text, separator)
  end

  defp trim_separator(text, ""), do: text

  defp trim_separator(text, separator) do
    text
    |> String.trim_leading(separator)
    |> String.trim_trailing(separator)
  end
end
