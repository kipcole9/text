defmodule Text.Word do

  def file_word_count(path) when is_binary(path) do
    path
    |> File.stream!
    |> word_count
  end

  def file_total_word_count(path) do
    path
    |> word_count()
    |> Enum.reduce(0, fn {_, count}, acc -> acc + count end)
  end

  def word_count(text) when is_binary(text) do
    text
    |> String.split
    |> word_count
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
    table = :ets.new(:words, [{:write_concurrency, true}, :public])

    stream
    |> Flow.flat_map(&String.split(&1))
    |> Flow.each(fn word ->
      :ets.update_counter(table, word, {2, 1}, {word, 0})
    end)
    |> Flow.run()

    :ets.tab2list(table)
  end

end