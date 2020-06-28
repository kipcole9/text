defmodule Text.Word do
  @moduledoc """
  Implements word counting for lists,
  streams and flows.

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

  * `splitter` is an arity-1 function
    that splits the text stream.
    The default is `&String.split/1`.

   ## Returns

   * A list of 2-tuples of the form
     `{word, count}` referred to as
     a frequency list.

  ## Examples

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
  Counts the total number of words in a
  frequency list.

  ## Arguments

  * `frequency_list` is a list of frequencies
    returned from `Text.Word.word_count/2`

   ## Returns

   * An integer number of words

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
