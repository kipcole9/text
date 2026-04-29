defmodule Text.Lemma do
  @moduledoc """
  Dictionary-driven lemmatization.

  Reduces an inflected word to its dictionary form (the *lemma*).
  Examples: `running → run`, `mice → mouse`, `cats → cat`.

  This module follows the same approach as Python's
  [`simplemma`](https://github.com/adbar/simplemma): a flat
  inflected-form-to-lemma lookup table per language. No POS tagging,
  no morphological analysis — just a dictionary. Coverage is broad
  for common vocabulary and unhelpful for rare or technical terms.

  ### Bundled and on-demand language packs

  English is bundled at compile time and loaded with zero I/O. Every
  other language pack from the upstream
  [`lemmatization-lists`](https://github.com/michmech/lemmatization-lists)
  project (Open Database License) is fetched on demand via
  `Text.Data`:

  * Loaded packs are cached under `:data_dir`/`lemma/` (default
    `~/.cache/text/lemma/`) and reused on subsequent calls.

  * Auto-download from upstream is **opt-in**, gated by
    `config :text, auto_download_lemma_data: true`. Without that
    flag, calls for an unbundled language raise an `ArgumentError`
    explaining the situation.

  * Or you can populate the cache manually by dropping the
    `lemmatization-<lang>.txt` file from upstream into the cache
    directory.

  ### Language input shapes

  The `:language` option accepts an atom (`:de`), a string (`"de"`,
  `"de-CH"`), or a `Localize.LanguageTag` struct. The base language
  subtag is used to pick the upstream file.

  Lookup is case-insensitive on the input; the returned lemma uses
  the casing of the dictionary entry. Unknown words are returned
  unchanged.

  """

  alias Text.Data

  @data_path "priv/lemma/lemmatization-en.txt"
  @external_resource @data_path

  @lemma_url_base "https://raw.githubusercontent.com/michmech/lemmatization-lists/master/"

  @doc """
  Returns the lemma of a single word.

  ### Arguments

  * `word` is a string. Lookup is case-insensitive.

  ### Options

  * `:language` is the language. Default `:en`. Accepts an atom, a
    string, or a `Localize.LanguageTag`.

  ### Returns

  * The lemma if known, otherwise the input unchanged.

  ### Examples

      iex> Text.Lemma.lemmatize("running")
      "run"

      iex> Text.Lemma.lemmatize("mice")
      "mouse"

      iex> Text.Lemma.lemmatize("xyznotaword")
      "xyznotaword"

  """
  @spec lemmatize(String.t(), keyword()) :: String.t()
  def lemmatize(word, options \\ []) when is_binary(word) do
    %{forms: forms} = data_for(language_input(options))
    key = String.downcase(word)
    Map.get(forms, key, word)
  end

  @doc """
  Lemmatizes every word in a string.

  ### Arguments

  * `text` is a string of zero or more words.

  ### Options

  * `:language` is the language. Default `:en`.

  ### Returns

  * A string with each word replaced by its lemma. Whitespace and
    surrounding punctuation are preserved as-is.

  ### Examples

      iex> Text.Lemma.lemmatize_text("the cats are running")
      "the cat be run"

  """
  @spec lemmatize_text(String.t(), keyword()) :: String.t()
  def lemmatize_text(text, options \\ []) when is_binary(text) do
    Regex.replace(~r/[\p{L}'-]+/u, text, fn match ->
      lemmatize(match, options)
    end)
  end

  @doc """
  Returns true if a word has a known lemma in the dictionary.

  ### Arguments

  * `word` is a string.

  ### Options

  * `:language` is the language. Default `:en`.

  ### Returns

  * `true` if the word appears as an inflected form in the
    dictionary, `false` otherwise. A word that *is* its own lemma
    only returns true if it also appears as an inflected form
    (e.g. `runs` is a form of `run`; `run` itself may not be a key).

  ### Examples

      iex> Text.Lemma.known?("running")
      true

      iex> Text.Lemma.known?("xyznotaword")
      false

  """
  @spec known?(String.t(), keyword()) :: boolean()
  def known?(word, options \\ []) when is_binary(word) do
    %{forms: forms} = data_for(language_input(options))
    Map.has_key?(forms, String.downcase(word))
  end

  @doc """
  Pre-loads a lemma dictionary for a language.

  Calling this is **optional**. The first lookup for a given
  language already triggers the same load (and, if enabled, the
  download). Use this to warm the cache during application startup
  or to register a custom dictionary under a name of your choosing.

  ### Forms

      load_language(language)
      load_language(language, tsv_path)

  Without an explicit path, the upstream URL is derived from the
  language input and the file is fetched via `Text.Data` (auto-download
  must be enabled for the network fetch to occur).

  ### Arguments

  * `language` is an atom, string, or `Localize.LanguageTag`.

  * `tsv_path` is an optional path to a TSV file with
    `lemma<TAB>form` entries.

  ### Returns

  * `:ok` on success.

  """
  @spec load_language(atom() | String.t() | struct()) :: :ok
  def load_language(language) do
    data = fetch_and_parse(language)
    cache_put(language, data)
    cache_put(lang_key(language), data)
    :ok
  end

  @spec load_language(atom() | String.t() | struct(), Path.t()) :: :ok
  def load_language(language, tsv_path) when is_binary(tsv_path) do
    data = parse_tsv(File.read!(tsv_path))
    cache_put(language, data)
    :ok
  end

  defp language_input(options), do: Keyword.get(options, :language, :en)

  defp data_for(input) do
    case lookup_cached(input) do
      {:ok, data} ->
        data

      :error ->
        key = lang_key(input)

        case lookup_cached(key) do
          {:ok, data} ->
            data

          :error ->
            data = load_for_key(key)
            cache_put(key, data)
            data
        end
    end
  end

  defp load_for_key("en") do
    @data_path
    |> Path.relative_to("priv")
    |> then(&Path.join(:code.priv_dir(:text), &1))
    |> File.read!()
    |> parse_tsv()
  end

  defp load_for_key(lang_key) do
    fetch_and_parse_key(lang_key)
  end

  defp fetch_and_parse(input) do
    fetch_and_parse_key(lang_key(input))
  end

  defp fetch_and_parse_key(lang_key) do
    filename = "lemmatization-#{lang_key}.txt"
    url = @lemma_url_base <> filename

    case Data.fetch(:lemma, filename, url: url) do
      {:ok, path} ->
        parse_tsv(File.read!(path))

      {:error, error} ->
        raise error
    end
  end

  defp lookup_cached(key) do
    case :persistent_term.get({__MODULE__, key}, nil) do
      nil -> :error
      data -> {:ok, data}
    end
  end

  defp cache_put(key, data) do
    :persistent_term.put({__MODULE__, key}, data)
  end

  defp lang_key(input) do
    input
    |> Text.Language.normalize()
    |> Atom.to_string()
  end

  defp parse_tsv(content) do
    forms =
      content
      |> String.replace_prefix("﻿", "")
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, "\t", parts: 2) do
          [lemma, form] -> Map.put(acc, String.downcase(form), lemma)
          _ -> acc
        end
      end)

    %{forms: forms}
  end
end
