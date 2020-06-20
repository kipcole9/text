defmodule Text.Word do
  @type frequencies :: [{String.t, pos_integer}, ...]

  def word_count(text) when is_binary(text) do
    word_count([text])
  end

  def word_count(list) when is_list(list) do
    list
    |> Flow.from_enumerable()
    |> word_count
  end

  def word_count(%File.Stream{} = stream) do
    stream
    |> Flow.from_enumerable()
    |> word_count
  end

  def word_count(%Flow{} = stream) do
    table = :ets.new(:word_count, [{:write_concurrency, true}, :public])

    stream
    |> Flow.flat_map(&String.split/1)
    |> Flow.map(&:ets.update_counter(table, &1, {2, 1}, {&1, 0}))
    |> Flow.run()

    list = :ets.tab2list(table)
    :ets.delete(table)

    list
  end

  @spec total_word_count(frequencies) :: pos_integer
  def total_word_count(frequencies) when is_list(frequencies) do
    Enum.reduce(frequencies, 0, fn {_word, count}, acc -> acc + count end)
  end

  @spec average_word_length(frequencies) :: float
  def average_word_length(frequencies) when is_list(frequencies) do
    {all, count} =
      Enum.reduce(frequencies, {0, 0}, fn {word, count}, {all, total_count} ->
        all = all + (String.length(word) * count)
        total_count = total_count + count
        {all, total_count}
      end)

    all / count
  end

  @spec sort(frequencies, :asc | :desc) :: frequencies
  def sort(frequencies, direction \\ :desc)

  def sort(frequencies, :desc) do
    Enum.sort(frequencies, &(elem(&1, 1) > elem(&2, 1)))
  end

  def sort(frequencies, :asc) do
    Enum.sort_by(frequencies, &elem(&1, 1))
  end

end
