defmodule Text.Stopwords do
  @moduledoc """
  Bundled multilingual stopword lists.

  Stopwords are the high-frequency function words that carry little
  topical content (`the`, `is`, `of` in English; `le`, `la`, `et` in
  French; …). They are routinely filtered out of text before frequency
  analysis, keyword extraction, or other content-focused processing.

  This module ships the [stopwords-iso](https://github.com/stopwords-iso/stopwords-iso)
  collection — a community-curated set of stopword lists covering
  ~60 languages, distributed under the MIT license. The raw `.txt`
  files live in `priv/stopwords/<lang>.txt`; this module loads them
  at compile time into per-language `MapSet`s and exposes a small
  query API.

  ### Languages

  Every list is keyed by its ISO 639-1 two-letter code. Use
  `available_languages/0` to enumerate the bundled set. Common codes
  include `:en`, `:fr`, `:de`, `:es`, `:it`, `:pt`, `:ru`, `:zh`,
  `:ja`, `:ar`, `:nl`, `:sv`, `:fi`, `:da`, `:no`, `:pl`, `:tr`,
  `:ko`, `:hi`, …

  ### Composing lists

  `union/2` merges two language sets — useful for code-mixed text or
  for adding the emoticon-equivalent token list. `extend/2` returns
  a new set with caller-supplied tokens added; that's how callers
  layer in domain-specific stopwords (e.g. boilerplate, brand names)
  without having to rebuild the whole list.

  ### Licensing

  The bundled `.txt` files are reproduced from stopwords-iso under
  the MIT license. See `priv/stopwords/LICENSE` for the upstream
  attribution. Regeneration is via `mix text.gen_stopwords`.

  """

  # Compile-time discovery of the bundled lists. Each .txt file under
  # priv/stopwords/ becomes a MapSet keyed by the filename stem (the
  # ISO 639-1 code) cast to an atom. Adding a new language is a matter
  # of dropping a new file in priv/stopwords/ and recompiling — no
  # changes to this module are required.
  @priv_dir Path.join([__DIR__, "..", "priv", "stopwords"])

  @sources @priv_dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".txt"))

  for source <- @sources do
    @external_resource Path.join(@priv_dir, source)
  end

  # Store as `%{lang => [string]}` rather than `%{lang => MapSet}`. A
  # `MapSet` baked into a module attribute at compile time loses its
  # opaque type tag through the ETF round-trip dialyzer applies to
  # persisted attributes, which then trips opacity warnings on
  # `MapSet.union/2` and `MapSet.member?/2`. Building the MapSet in
  # `for/1` (cached in `:persistent_term` after first call) keeps the
  # public surface MapSet-typed without paying that cost more than once
  # per language.
  load = fn path ->
    path
    |> File.read!()
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  @stopword_lists (for source <- @sources, into: %{} do
                     lang =
                       source
                       |> String.replace_suffix(".txt", "")
                       |> String.to_atom()

                     {lang, load.(Path.join(@priv_dir, source))}
                   end)

  @available_languages @stopword_lists |> Map.keys() |> Enum.sort()

  @typedoc "An ISO 639-1 language code, atom-typed."
  @type language :: atom()

  @typedoc """
  Anything `Text.Language.normalize/1` accepts: an atom language tag, a
  BCP-47 string, or a `Localize.LanguageTag` struct.
  """
  @type language_input :: atom() | String.t() | struct()

  @doc """
  Returns the bundled stopword `MapSet` for a language.

  ### Arguments

  * `language` is an atom language tag (`:en`, `:fr`, …), a string
    BCP-47 tag (`"en"`, `"en-US"`), or a `Localize.LanguageTag` struct.
    The input is normalised via `Text.Language.normalize/1` before
    lookup.

  ### Returns

  * A `MapSet` of lowercased stopword strings.

  * Raises `ArgumentError` if no list is bundled for the resolved
    language. Use `available_languages/0` to enumerate the supported
    set.

  ### Examples

      iex> Text.Stopwords.for(:en) |> MapSet.member?("the")
      true

      iex> Text.Stopwords.for("fr") |> MapSet.member?("le")
      true

      iex> Text.Stopwords.for(:en) |> MapSet.member?("zebra")
      false

  """
  @spec for(language_input()) :: MapSet.t(String.t())
  def for(language) do
    lang = Text.Language.normalize(language)

    case Map.fetch(@stopword_lists, lang) do
      {:ok, words} ->
        # `MapSet.new/1` from a ~1k-entry list runs in microseconds,
        # and rebuilding each call keeps dialyzer's opacity chain
        # intact (a `:persistent_term`-cached set would lose its
        # opaque tag through the `term()`-returning fetch).
        MapSet.new(words)

      :error ->
        raise ArgumentError,
              "no bundled stopword list for #{inspect(lang)}. " <>
                "Use Text.Stopwords.available_languages/0 to enumerate the supported set."
    end
  end

  @doc """
  Returns whether `token` is in the bundled stopword list for a language.

  Equivalent to `MapSet.member?(Text.Stopwords.for(language), token)`,
  with the same input flexibility on the `language` argument.

  ### Arguments

  * `language` is any value accepted by `for/1`.

  * `token` is a string. Comparison is case-sensitive against the
    lowercased upstream lists; pass a folded token if you need
    case-insensitive matching.

  ### Returns

  * `true` if the token is in the list, `false` otherwise.

  ### Examples

      iex> Text.Stopwords.contains?(:en, "the")
      true

      iex> Text.Stopwords.contains?(:en, "Zebra")
      false

      iex> Text.Stopwords.contains?(:fr, "le")
      true

  """
  # `for/1`'s return value loses dialyzer's opaque tag through the
  # `__MODULE__.` qualified-call boundary; the warning is benign.
  @dialyzer {:nowarn_function, contains?: 2, union: 2}
  @spec contains?(language_input(), String.t()) :: boolean()
  def contains?(language, token) when is_binary(token) do
    MapSet.member?(__MODULE__.for(language), token)
  end

  @doc """
  Returns the sorted list of bundled language tags.

  ### Returns

  * A list of atom language tags (ISO 639-1 codes).

  ### Examples

      iex> :en in Text.Stopwords.available_languages()
      true

      iex> :fr in Text.Stopwords.available_languages()
      true

      iex> Text.Stopwords.available_languages() |> length() > 50
      true

  """
  @spec available_languages() :: [language()]
  def available_languages, do: @available_languages

  @doc """
  Returns whether a stopword list is bundled for the given language.

  ### Arguments

  * `language` is any value accepted by `for/1`.

  ### Returns

  * `true` if a list is bundled, `false` otherwise.

  ### Examples

      iex> Text.Stopwords.available?(:en)
      true

      iex> Text.Stopwords.available?(:zz)
      false

  """
  @spec available?(language_input()) :: boolean()
  def available?(language) do
    Map.has_key?(@stopword_lists, Text.Language.normalize(language))
  end

  @doc """
  Returns the union of two bundled stopword sets.

  Useful for code-mixed input (e.g. a French-English document) or for
  layering in a small auxiliary set (an `:emoticon`-style list).

  ### Arguments

  * `first` and `second` are anything accepted by `for/1`.

  ### Returns

  * A `MapSet` containing every token from either list.

  ### Examples

      iex> set = Text.Stopwords.union(:en, :fr)
      iex> MapSet.member?(set, "the") and MapSet.member?(set, "le")
      true

  """
  @spec union(language_input(), language_input()) :: MapSet.t(String.t())
  def union(first, second) do
    MapSet.union(__MODULE__.for(first), __MODULE__.for(second))
  end

  @doc """
  Returns a stopword set augmented with extra tokens.

  Lets callers layer domain-specific stopwords (e.g. brand names,
  boilerplate, navigation chrome) on top of the bundled list without
  mutating the bundled set.

  ### Arguments

  * `language` is any value accepted by `for/1`.

  * `extra` is a list, `MapSet`, or any enumerable of strings to add.

  ### Returns

  * A `MapSet` containing the bundled set plus `extra`.

  ### Examples

      iex> set = Text.Stopwords.extend(:en, ["acme", "lorem"])
      iex> MapSet.member?(set, "the") and MapSet.member?(set, "acme")
      true

  """
  @spec extend(language_input(), Enumerable.t(String.t())) :: MapSet.t(String.t())
  def extend(language, extra) do
    base = __MODULE__.for(language)

    Enum.reduce(extra, base, fn token, acc when is_binary(token) ->
      MapSet.put(acc, token)
    end)
  end
end
