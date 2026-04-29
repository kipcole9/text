defmodule Text.Hyphenation do
  @moduledoc """
  Hyphenation via Liang's algorithm with TeX hyphenation patterns.

  Returns the legal hyphenation points for a word — the positions
  where a soft hyphen could be inserted for line-breaking, and where
  a syllable boundary lies. This is the engine that backs both
  hyphenation (`hyphenate/2`) and pattern-based syllable counting
  (`count/2`).

  ### Bundled and on-demand language packs

  American English (`hyph-en-us`, ~5,000 patterns plus DEK's
  exception list) is bundled and loaded at compile time, so the
  default English path is zero-I/O. Every other hyph-utf8 language
  pack — French, German, Spanish, Russian, Hindi, and ~80 others —
  can be loaded on demand from the
  [hyph-utf8](https://github.com/hyphenation/tex-hyphen) upstream.

  On-demand loading goes through `Text.Data`, which means:

  * Loaded language packs are cached under `:data_dir`
    (default `~/.cache/text/hyphenation/`) so subsequent calls do
    no I/O beyond the cache lookup.

  * Auto-download from upstream is **opt-in**, gated by
    `config :text, auto_download_hyphenation_data: true`. Without
    that flag the package never reaches out to the network — calls
    for an unbundled language raise an `ArgumentError` explaining
    the situation.

  * If you would rather populate the cache manually, drop the
    `hyph-<tag>.tex` file from upstream into the configured
    `:data_dir`/`hyphenation/` directory and it will be picked up
    without any download.

  Bundled file: `priv/hyphenation/hyph-en-us.tex`, distributed under
  a permissive Knuth-style license (copying and distribution
  permitted in any medium provided the original copyright notice
  is preserved).

  ### Language input shapes

  Every option that takes a `:language` accepts:

  * an atom (`:fr`, `:"de-1996"`),

  * a string (`"fr"`, `"en-GB"`, `"de-CH"`),

  * or a `Localize.LanguageTag` struct (when the optional
    [`localize`](https://hex.pm/packages/localize) dependency is
    loaded). The `:language` and `:territory` fields are used to
    derive the upstream file tag.

  The mapping prefers the most common variant when the input is
  ambiguous: `:en` resolves to `en-us`, `:de` to the modern
  spelling `de-1996`, `:el` to monotonic Greek, etc. Pass an
  explicit BCP-47 tag (`"en-GB"`, `"de-CH"`, `"de-1901"`) to
  override.

  ### Left and right minima

  TeX hyphenation patterns are designed with minimum gaps at the
  start and end of a word — `\\lefthyphenmin` and `\\righthyphenmin`.
  The American English file recommends `left: 2`, `right: 3`. The
  recommended values are read from the upstream `.tex` file's
  header when available, and applied as defaults in `hyphenate/2`,
  `points/2`, and `count/2`. They can be overridden per-call via
  the `:left_min` and `:right_min` options.

  """

  alias Text.Data
  alias Text.Hyphenation.Parser

  @data_path "priv/hyphenation/hyph-en-us.tex"
  @external_resource @data_path

  {patterns, exceptions} = Parser.parse_tex(File.read!(@data_path))

  @patterns_en_us patterns
  @exceptions_en_us exceptions
  @left_min_en_us 2
  @right_min_en_us 3

  @hyph_url_base "https://raw.githubusercontent.com/hyphenation/tex-hyphen/master/hyph-utf8/tex/generic/hyph-utf8/patterns/tex/"

  # BCP-47 → hyph-utf8 file tag. Covers cases where the bare language
  # code or an obvious BCP-47 form needs a regional/script-specific file.
  # Anything not in this map falls through to the language code itself.
  @hyphenation_tags %{
    "en" => "en-us",
    "en-us" => "en-us",
    "en-gb" => "en-gb",
    "de" => "de-1996",
    "de-de" => "de-1996",
    "de-at" => "de-1996",
    "de-ch" => "de-ch-1901",
    "de-1901" => "de-1901",
    "de-1996" => "de-1996",
    "el" => "el-monoton",
    "el-monoton" => "el-monoton",
    "el-polyton" => "el-polyton",
    "fi-x-school" => "fi-x-school",
    "grc-x-ibycus" => "grc-x-ibycus",
    "la-x-classic" => "la-x-classic",
    "la-x-liturgic" => "la-x-liturgic",
    "mn" => "mn-cyrl",
    "mn-cyrl" => "mn-cyrl",
    "mn-cyrl-x-lmc" => "mn-cyrl-x-lmc",
    "mul-ethi" => "mul-ethi",
    "sh" => "sh-latn",
    "sh-cyrl" => "sh-cyrl",
    "sh-latn" => "sh-latn",
    "sr" => "sr-cyrl",
    "sr-cyrl" => "sr-cyrl",
    "zh" => "zh-latn-pinyin",
    "zh-latn-pinyin" => "zh-latn-pinyin"
  }

  @doc """
  Returns the list of valid hyphenation points within a word.

  A hyphenation point is the number of characters from the start of
  the word at which a hyphen is permitted. For example, the points
  of `"hyphenation"` are `[2, 5, 7]`, indicating breaks `hy-phen-a-tion`
  (two characters from the left is the first break, and so on).

  ### Arguments

  * `word` is a single word as a string. Surrounding punctuation is
    not stripped — pass tokens that have already been split.

  ### Options

  * `:language` is the hyphenation language. The default is `:en`
    (American English). Other languages must first be loaded with
    `load_language/2`.

  * `:left_min` is the minimum number of characters at the start of
    the word before the first allowed break. Default is the
    language's recommended value (`2` for English).

  * `:right_min` is the minimum number of characters at the end of
    the word after the last allowed break. Default is the
    language's recommended value (`3` for English).

  ### Returns

  * A list of integer hyphenation points, in ascending order. An
    empty list means no legal break points exist (very short words,
    or words below the left/right minima).

  ### Examples

      iex> Text.Hyphenation.points("hyphenation")
      [2, 6]

      iex> Text.Hyphenation.points("computer")
      [3]

      iex> Text.Hyphenation.points("a")
      []

  """
  @spec points(String.t(), keyword()) :: [pos_integer()]
  def points(word, options \\ []) when is_binary(word) do
    language = Keyword.get(options, :language, :en)
    {patterns, exceptions, default_left, default_right} = data_for(language)

    left_min = Keyword.get(options, :left_min, default_left)
    right_min = Keyword.get(options, :right_min, default_right)

    word_lower = String.downcase(word)
    word_len = String.length(word_lower)

    raw =
      case Map.get(exceptions, word_lower) do
        nil -> compute_points(word_lower, patterns)
        exception_points -> exception_points
      end

    Enum.filter(raw, fn p -> p >= left_min and p <= word_len - right_min end)
  end

  @doc """
  Inserts soft hyphens at every legal break point in a word.

  ### Arguments

  * `word` is a single word as a string.

  ### Options

  * `:hyphen` is the string inserted at each break point. Default is
    `"-"`. For typesetting use, `"\\u00AD"` (soft hyphen) is common.

  * `:language`, `:left_min`, `:right_min` — see `points/2`.

  ### Returns

  * The word with the hyphen string inserted at every break point.

  ### Examples

      iex> Text.Hyphenation.hyphenate("hyphenation")
      "hy-phen-ation"

      iex> Text.Hyphenation.hyphenate("computer", hyphen: "·", right_min: 1)
      "com·put·er"

  """
  @spec hyphenate(String.t(), keyword()) :: String.t()
  def hyphenate(word, options \\ []) when is_binary(word) do
    hyphen = Keyword.get(options, :hyphen, "-")
    points = points(word, options)
    insert_hyphens(word, points, hyphen)
  end

  @doc """
  Returns the number of syllables in a word, using hyphenation
  pattern boundaries as a proxy for syllable boundaries.

  This is more accurate than the heuristic in `Text.Syllable.count/2`
  for words that match the bundled patterns, but the two
  occasionally disagree on edge cases. For readability metrics, use
  `Text.Syllable`. For typographic syllable count, prefer this.

  ### Arguments

  * `word` is a single word as a string.

  ### Options

  * `:language`, `:left_min`, `:right_min` — see `points/2`.

  ### Returns

  * A positive integer: the number of break points plus one.

  ### Examples

      iex> Text.Hyphenation.count("hyphenation")
      3

      iex> Text.Hyphenation.count("cat")
      1

  """
  @spec count(String.t(), keyword()) :: pos_integer()
  def count(word, options \\ []) when is_binary(word) do
    length(points(word, Keyword.merge([left_min: 1, right_min: 1], options))) + 1
  end

  @doc """
  Pre-loads a hyphenation pattern file for a language.

  Calling this is **optional**. The first call to `points/2`,
  `hyphenate/2`, or `count/2` for a given language already loads
  (and if necessary downloads) the pattern file via `Text.Data` —
  `load_language/1,2,3` is a way to warm the cache up front (e.g.
  during application startup) so the first user-facing call has
  no latency, or to register a custom pattern file under a name of
  your choosing.

  ### Forms

      load_language(language)
      load_language(language, options)
      load_language(language, tex_path)
      load_language(language, tex_path, options)

  Without an explicit `tex_path`, the upstream URL is derived from
  the language input and the file is fetched via `Text.Data` (see
  the moduledoc — auto-download must be enabled for the network
  fetch to occur).

  With an explicit `tex_path`, that file is read directly and
  registered under `language`.

  ### Arguments

  * `language` is an atom identifying the language (e.g. `:de`,
    `:"de-ch"`, `:my_custom_language`).

  * `tex_path` is an optional path to a TeX hyphenation pattern
    file. When omitted, the file is resolved through `Text.Data`.

  ### Options

  * `:left_min` is the minimum left hyphenation distance for the
    language. Default is parsed from the file's header, falling
    back to `2`.

  * `:right_min` is the minimum right hyphenation distance for the
    language. Default is parsed from the file's header, falling
    back to `2`.

  ### Returns

  * `:ok` on success.

  """
  @spec load_language(atom()) :: :ok
  def load_language(language) when is_atom(language) do
    load_language_auto(language, [])
  end

  @spec load_language(atom(), keyword() | Path.t()) :: :ok
  def load_language(language, options) when is_atom(language) and is_list(options) do
    load_language_auto(language, options)
  end

  def load_language(language, tex_path) when is_atom(language) and is_binary(tex_path) do
    load_language_from_path(language, tex_path, [])
  end

  @spec load_language(atom(), Path.t(), keyword()) :: :ok
  def load_language(language, tex_path, options)
      when is_atom(language) and is_binary(tex_path) and is_list(options) do
    load_language_from_path(language, tex_path, options)
  end

  defp load_language_auto(language, options) do
    hyph_tag = resolve_hyph_tag(language)
    data = fetch_and_parse(hyph_tag, options)
    cache_put(language, data)
    cache_put(hyph_tag, data)
    :ok
  end

  defp load_language_from_path(language, tex_path, options) do
    content = File.read!(tex_path)
    data = parse_data(content, options)
    cache_put(language, data)
    :ok
  end

  defp data_for(input) do
    case lookup_cached(input) do
      {:ok, data} ->
        data

      :error ->
        hyph_tag = resolve_hyph_tag(input)

        case lookup_cached(hyph_tag) do
          {:ok, data} ->
            data

          :error ->
            data = load_for_tag(hyph_tag)
            cache_put(hyph_tag, data)
            data
        end
    end
  end

  defp load_for_tag("en-us") do
    {@patterns_en_us, @exceptions_en_us, @left_min_en_us, @right_min_en_us}
  end

  defp load_for_tag(hyph_tag) do
    fetch_and_parse(hyph_tag, [])
  end

  defp fetch_and_parse(hyph_tag, options) do
    filename = "hyph-#{hyph_tag}.tex"
    url = @hyph_url_base <> filename

    case Data.fetch(:hyphenation, filename, url: url) do
      {:ok, path} ->
        parse_data(File.read!(path), options)

      {:error, error} ->
        raise error
    end
  end

  defp parse_data(content, options) do
    {patterns, exceptions} = Parser.parse_tex(content)
    {header_left, header_right} = parse_hyphenmins(content)
    left_min = Keyword.get(options, :left_min, header_left)
    right_min = Keyword.get(options, :right_min, header_right)
    {patterns, exceptions, left_min, right_min}
  end

  defp parse_hyphenmins(content) do
    left =
      case Regex.run(~r/^%\s*left:\s*(\d+)/m, content) do
        [_, n] -> String.to_integer(n)
        _ -> 2
      end

    right =
      case Regex.run(~r/^%\s*right:\s*(\d+)/m, content) do
        [_, n] -> String.to_integer(n)
        _ -> 2
      end

    {left, right}
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

  defp resolve_hyph_tag(input) do
    bcp47 =
      input
      |> Text.Language.to_locale_string()
      |> String.downcase()
      |> String.replace("_", "-")

    case Map.get(@hyphenation_tags, bcp47) do
      nil ->
        # Try the language part alone (e.g. "fr-CA" → "fr").
        lang_only = String.split(bcp47, "-") |> hd()
        Map.get(@hyphenation_tags, lang_only, lang_only)

      tag ->
        tag
    end
  end

  # Liang's algorithm: gather pattern priorities at every gap inside
  # the dotted word, then return positions where the maximum priority
  # is odd.
  defp compute_points(word, patterns) do
    dotted = "." <> word <> "."
    chars = String.to_charlist(dotted)
    n = length(chars)
    gaps = n - 1

    initial = Tuple.duplicate(0, gaps)

    priorities =
      Enum.reduce(0..(n - 1), initial, fn start, acc ->
        Enum.reduce(1..(n - start), acc, fn len, acc2 ->
          substring = chars |> Enum.slice(start, len) |> List.to_string()

          case Map.get(patterns, substring) do
            nil -> acc2
            pattern_priorities -> apply_priorities(acc2, pattern_priorities, start - 1, gaps)
          end
        end)
      end)

    word_len = n - 2

    priorities
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.flat_map(fn {priority, gap_index} ->
      word_position = gap_index

      cond do
        word_position <= 0 -> []
        word_position >= word_len -> []
        rem(priority, 2) == 1 -> [word_position]
        true -> []
      end
    end)
  end

  defp apply_priorities(acc, pattern_priorities, base_offset, gaps) do
    pattern_priorities
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {priority, i}, acc ->
      gap = base_offset + i

      if gap >= 0 and gap < gaps do
        current = elem(acc, gap)
        if priority > current, do: put_elem(acc, gap, priority), else: acc
      else
        acc
      end
    end)
  end

  defp insert_hyphens(word, [], _hyphen), do: word

  defp insert_hyphens(word, points, hyphen) do
    graphemes = String.graphemes(word)
    do_insert(graphemes, 0, points, hyphen, [])
  end

  defp do_insert([], _idx, _points, _hyphen, acc) do
    acc |> Enum.reverse() |> Enum.join()
  end

  defp do_insert([g | rest], idx, [p | points_rest], hyphen, acc) when idx == p do
    do_insert(rest, idx + 1, points_rest, hyphen, [g, hyphen | acc])
  end

  defp do_insert([g | rest], idx, points, hyphen, acc) do
    do_insert(rest, idx + 1, points, hyphen, [g | acc])
  end
end
