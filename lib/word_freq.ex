defmodule Text.WordFreq do
  @moduledoc """
  Word frequency lookup tables.

  A drop-in equivalent of Python's
  [`wordfreq`](https://pypi.org/project/wordfreq/) for the use cases
  that matter most: ranking candidate words during spell correction,
  filtering rare-but-not-OOV terms in keyword extraction, and
  reporting how common a word is on a human-readable scale.

  ### Bundled and on-demand language packs

  English is bundled at compile time (top ~30,000 American English
  words from the Google Web Trillion Word Corpus, via Peter
  Norvig's distribution at <https://norvig.com/ngrams/>) and
  loaded with zero I/O. Other languages are resolved through
  `Text.Data` from the cache directory (`:data_dir`/`wordfreq/`,
  default `~/.cache/text/wordfreq/`).

  Unlike `Text.Hyphenation` and `Text.Lemma`, there is no canonical
  per-language download URL for word-frequency data — the upstream
  Python `wordfreq` library packages its data internally. Set
  `auto_download_wordfreq_data: true` and call `load_language/2`
  with an explicit URL/path when you have a frequency table to
  register, or drop pre-built `<lang>.tsv` files into the cache
  directory.

  Frequency tables are loaded lazily on first access and cached in
  `:persistent_term` for the lifetime of the runtime, so subsequent
  calls are essentially free.

  ### Language input shapes

  Every option that takes a `:language` accepts an atom (`:fr`), a
  string (`"fr"`, `"fr-CA"`), or a `Localize.LanguageTag`. The base
  language subtag is used for lookup.

  ### Zipf scale

  The Zipf scale, popularised by Marc Brysbaert and reproduced by
  the Python `wordfreq` library, expresses frequency as
  `log10(count_per_billion) = log10(frequency) + 9`. Useful values:

  * 7+ — extremely common (`the`, `of`, `and`).
  * 5-6 — common conversational vocabulary.
  * 3-4 — recognisable, less frequent.
  * 1-2 — rare or technical.
  * 0   — not in the corpus at all.

  """

  alias Text.Data

  @data_path "priv/wordfreq/en.tsv"
  @external_resource @data_path

  @doc """
  Returns the raw corpus count of a word in the chosen language.

  ### Arguments

  * `word` is a string. The lookup is case-insensitive.

  ### Options

  * `:language` is the language. The default is `:en`.

  ### Returns

  * A non-negative integer count. Returns `0` for unknown words.

  ### Examples

      iex> Text.WordFreq.count("the") > Text.WordFreq.count("rare")
      true

      iex> Text.WordFreq.count("the_definitely_not_a_real_word_xyz")
      0

  """
  @spec count(String.t(), keyword()) :: non_neg_integer()
  def count(word, options \\ []) when is_binary(word) do
    %{counts: counts} = data_for(language_input(options))
    Map.get(counts, String.downcase(word), 0)
  end

  @doc """
  Returns the normalised frequency of a word: count divided by the
  corpus total.

  ### Arguments

  * `word` is a string.

  ### Options

  * `:language` is the language. The default is `:en`.

  ### Returns

  * A float between `0.0` and `1.0`. Returns `0.0` for unknown words.

  ### Examples

      iex> Text.WordFreq.frequency("the") > 0.0
      true

      iex> Text.WordFreq.frequency("definitely_not_a_real_word_xyz")
      0.0

  """
  @spec frequency(String.t(), keyword()) :: float()
  def frequency(word, options \\ []) when is_binary(word) do
    %{counts: counts, total: total} = data_for(language_input(options))

    case Map.get(counts, String.downcase(word)) do
      nil -> 0.0
      0 -> 0.0
      n when total > 0 -> n / total
      _ -> 0.0
    end
  end

  @doc """
  Returns the Zipf score of a word: `log10(frequency) + 9`.

  ### Arguments

  * `word` is a string.

  ### Options

  * `:language` is the language. The default is `:en`.

  ### Returns

  * A float Zipf score, or `0.0` for unknown words.

  ### Examples

      iex> Text.WordFreq.zipf("the") > 6.0
      true

      iex> Text.WordFreq.zipf("definitely_not_a_real_word_xyz")
      0.0

  """
  @spec zipf(String.t(), keyword()) :: float()
  def zipf(word, options \\ []) when is_binary(word) do
    case frequency(word, options) do
      f when f == 0.0 -> 0.0
      f -> :math.log10(f) + 9
    end
  end

  @doc """
  Returns the descending-frequency rank of a word.

  Rank `1` is the most frequent word in the corpus.

  ### Arguments

  * `word` is a string.

  ### Options

  * `:language` is the language. The default is `:en`.

  ### Returns

  * A positive integer rank, or `nil` for unknown words.

  ### Examples

      iex> Text.WordFreq.rank("the")
      1

      iex> Text.WordFreq.rank("definitely_not_a_real_word_xyz")
      nil

  """
  @spec rank(String.t(), keyword()) :: pos_integer() | nil
  def rank(word, options \\ []) when is_binary(word) do
    %{ranks: ranks} = data_for(language_input(options))
    Map.get(ranks, String.downcase(word))
  end

  @doc """
  Returns the top `n` most frequent words in the language.

  ### Arguments

  * `n` is the number of entries to return.

  ### Options

  * `:language` is the language. The default is `:en`.

  ### Returns

  * A list of `{word, count}` tuples, ordered by descending count.

  ### Examples

      iex> [{first, _} | _] = Text.WordFreq.top(5)
      iex> first
      "the"

  """
  @spec top(pos_integer(), keyword()) :: [{String.t(), pos_integer()}]
  def top(n, options \\ []) when is_integer(n) and n > 0 do
    %{ordered: ordered} = data_for(language_input(options))
    Enum.take(ordered, n)
  end

  @doc """
  Returns the size of the loaded vocabulary for a language.

  ### Arguments

  * No positional arguments.

  ### Options

  * `:language` is the language. The default is `:en`.

  ### Returns

  * The number of distinct words in the loaded frequency table.

  ### Examples

      iex> Text.WordFreq.vocabulary_size() > 1000
      true

  """
  @spec vocabulary_size(keyword()) :: non_neg_integer()
  def vocabulary_size(options \\ []) do
    %{counts: counts} = data_for(language_input(options))
    map_size(counts)
  end

  @doc """
  Pre-loads a frequency table for a language.

  Calling this is **optional** when the file already lives in the
  cache directory under `<lang>.tsv` — the first lookup will pick
  it up automatically. Use this to warm the cache during application
  startup or to register a custom dictionary under a name of your
  choosing.

  ### Forms

      load_language(language)
      load_language(language, tsv_path)

  Without an explicit path, the file is resolved through `Text.Data`
  (the cache directory is consulted; no canonical URL is configured
  for `:wordfreq`, so download is not attempted).

  ### Arguments

  * `language` is an atom, string, or `Localize.LanguageTag`.

  * `tsv_path` is an optional path to a TSV file with
    `word<TAB>count` entries.

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
    filename = "#{lang_key}.tsv"

    case Data.fetch(:wordfreq, filename) do
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
    entries =
      content
      |> String.split("\n", trim: true)
      |> Enum.map(&parse_line/1)
      |> Enum.reject(&is_nil/1)

    counts = Map.new(entries)
    total = Enum.reduce(entries, 0, fn {_w, c}, acc -> acc + c end)

    ordered =
      entries
      |> Enum.sort_by(fn {_w, c} -> -c end)

    ranks =
      ordered
      |> Enum.with_index(1)
      |> Map.new(fn {{word, _count}, rank} -> {word, rank} end)

    %{counts: counts, total: total, ordered: ordered, ranks: ranks}
  end

  defp parse_line(line) do
    case String.split(line, "\t", parts: 2) do
      [word, count_str] ->
        case Integer.parse(count_str) do
          {count, _rest} -> {String.downcase(word), count}
          :error -> nil
        end

      _ ->
        nil
    end
  end
end
