defmodule Text.Word do
  @moduledoc """
  Implements word counting for lists, streams and flows.

  ## Tokenization

  Word counting separates a text into tokens via a caller-supplied
  splitter function. The **default splitter is `String.split/1`**,
  which splits only on Unicode whitespace. This default has two
  important properties to be aware of:

  * **It does not implement Unicode word segmentation (UAX #29).**
    `String.split/1` is a fast byte-level whitespace split. It does
    not respect the boundary rules in
    [UAX #29](https://unicode.org/reports/tr29/) — for example, it
    keeps `don't`, `co-operate`, `U.S.`, and `1,200` as single
    tokens, where UAX #29 would emit several. For frequency counting
    this is usually the desired behaviour, but if you need standards-
    compliant boundaries (e.g. for cursor movement, search
    highlighting, or linguistic analysis) pass an explicit splitter
    that delegates to `Unicode.String.split/2`. See examples below.

  * **It does not work for languages that don't use whitespace
    between words.** Chinese, Japanese, Korean, Thai, Lao, Khmer, and
    Burmese (Myanmar) write running text without spaces. Calling
    `word_count/1` on text in those languages with the default
    splitter will return the entire passage (or large punctuation-
    delimited chunks of it) as a single "word". For these languages
    you must pass a splitter that uses dictionary-based segmentation,
    e.g. `&Unicode.String.split(&1, break: :word, locale: :zh,
    trim: true)`.

  ### Choosing a splitter

  | Splitter | Behaviour | When to use |
  |---|---|---|
  | `&String.split/1` (default) | Whitespace only, ~50–100× faster than UAX | English / Western prose, fast counting |
  | `&Unicode.String.split(&1, break: :word, trim: true)` | UAX #29 segmentation | Standards-compliant boundaries; required for CJK/SE-Asian text (with `:locale`) |
  | `&Regex.split(~r/\\W+/u, &1, trim: true)` | Alphabetic runs only | Strip all punctuation, ASCII-only words |

  Note that `Unicode.String.split/2` with `break: :word` produces
  punctuation tokens (`","`, `"."`, `"'"`, etc.) as their own words.
  Filter or rejoin those before frequency counting if you only want
  alphabetic tokens.
  """

  @typedoc "Enumerable types for word counting"
  @type text :: Flow.t() | File.Stream.t() | String.t() | [String.t(), ...]

  @typedoc "A list of words and their frequencies in a text"
  @type frequency_list :: [{String.t(), pos_integer}, ...]

  @typedoc "A function to split text"
  @type splitter :: function()

  @doc """
  Counts the number of words in a string,
  `File.Stream`, or `Flow`.

  ## Arguments

  * `text` is either a `String.t`, `Flow.t`,
    `File.Stream.t` or a list of strings.

  * `splitter` is an arity-1 function that takes a string and
    returns a list of tokens. The default is `&String.split/1`,
    which splits only on Unicode whitespace.

  ## Returns

  * A list of 2-tuples of the form `{word, count}`,
    referred to as a frequency list.

  ## Important: the default splitter

  The default `&String.split/1` is fast but **does not** implement
  Unicode word segmentation (UAX #29) and **does not** work for
  languages that write without spaces between words (Chinese,
  Japanese, Korean, Thai, Lao, Khmer, Burmese). On such input the
  whole passage will be returned as a single token (or as a small
  number of punctuation-delimited chunks).

  See the module documentation for a full discussion of splitter
  choices.

  ## Examples

      # English / Western prose — default splitter is fine.
      Text.Word.word_count("the quick brown fox the lazy dog")
      #=> [{"the", 2}, {"quick", 1}, {"brown", 1}, ...]

      # Chinese — must use dictionary-aware UAX segmentation.
      splitter = &Unicode.String.split(&1, break: :word, locale: :zh, trim: true)
      Text.Word.word_count("中文文本不使用空格", splitter)

      # Standards-compliant Western tokenization, with punctuation
      # tokens filtered out.
      uax_alpha = fn text ->
        text
        |> Unicode.String.split(break: :word, trim: true)
        |> Enum.reject(&Regex.match?(~r/^\\W+$/u, &1))
      end
      Text.Word.word_count("Don't stop — believe!", uax_alpha)

  """
  @spec word_count(Flow.t() | File.Stream.t() | String.t() | [String.t()], splitter) ::
          frequency_list

  def word_count(text, splitter \\ &String.split/1)

  def word_count(text, splitter) when is_binary(text) do
    word_count([text], splitter)
  end

  def word_count(list, splitter) when is_list(list) do
    list
    |> Flow.from_enumerable()
    |> word_count(splitter)
  end

  def word_count(%File.Stream{} = stream, splitter) do
    stream
    |> Flow.from_enumerable()
    |> word_count(splitter)
  end

  def word_count(%Flow{} = stream, splitter) do
    table = :ets.new(:word_count, [{:write_concurrency, true}, :public])

    stream
    |> Flow.flat_map(splitter)
    |> Flow.map(&:ets.update_counter(table, &1, {2, 1}, {&1, 0}))
    |> Flow.run()

    list = :ets.tab2list(table)
    :ets.delete(table)

    list
  end

  @doc """
  Counts the total number of words in a frequency list.

  ## Arguments

  * `frequency_list` is a list of frequencies returned from
    `Text.Word.word_count/2`.

  ## Returns

  * An integer number of words.

  ## Notes

  The total reflects whatever tokenization was used to build
  `frequency_list`. With the default `String.split/1` splitter the
  count is the number of whitespace-separated tokens, which:

  * counts contractions (`don't`), hyphenations (`co-operate`),
    abbreviations (`U.S.`) and decimals (`1,200`) as a single word
    each — typically what a frequency-counter wants;

  * undercounts radically on Chinese / Japanese / Korean / Thai /
    Lao / Khmer / Burmese, where the entire input may collapse to a
    single token. Use a UAX/dictionary-aware splitter via
    `word_count/2` for those languages.

  ## Examples

  """
  @spec total_word_count(frequency_list) :: pos_integer
  def total_word_count(frequency_list) when is_list(frequency_list) do
    Enum.reduce(frequency_list, 0, fn {_word, count}, acc -> acc + count end)
  end

  @doc """
  Counts the average word length in a
  frequency list.

  ## Arguments

  * `frequency_list` is a list of frequencies
    returned from `Text.Word.word_count/2`

   ## Returns

   * An float representing the
     average word length

  ## Examples

  """
  @spec average_word_length(frequency_list) :: float
  def average_word_length(frequency_list) when is_list(frequency_list) do
    {all, count} =
      Enum.reduce(frequency_list, {0, 0}, fn {word, count}, {all, total_count} ->
        all = all + String.length(word) * count
        total_count = total_count + count
        {all, total_count}
      end)

    all / count
  end

  @doc """
  Sorts the words in words in a
  frequency list.

  ## Arguments

  * `frequency_list` is a list of frequencies
    returned from `Text.Word.word_count/2`

  * `directions` is either `:asc` or
    `:desc`. The default is `:desc`.

   ## Returns

  * The `frequency_list` sorted in the
   direction specified

  ## Examples

  """
  @spec sort(frequency_list, :asc | :desc) :: frequency_list
  def sort(frequency_list, direction \\ :desc)

  def sort(frequency_list, :desc) do
    Enum.sort(frequency_list, &(elem(&1, 1) > elem(&2, 1)))
  end

  def sort(frequency_list, :asc) do
    Enum.sort_by(frequency_list, &elem(&1, 1))
  end
end
