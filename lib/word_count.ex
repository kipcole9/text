defmodule Text.Word do

  def parallel_count(path) when is_binary(path) do
    path
    |> File.stream!
    |> parallel_count
  end

  def parallel_count(%File.Stream{} = stream) do
    table = :ets.new(:words, [{:write_concurrency, true}, :public])
    pattern = :binary.compile_pattern([" ", "\n"])

    stream
    |> Flow.from_enumerable()
    |> Flow.flat_map(&String.split(&1, pattern))
    |> Flow.each(fn word ->
      :ets.update_counter(table, word, {2, 1}, {word, 0})
    end)
    |> Flow.run()

    :ets.tab2list(table)
  end

  def count(path) when is_binary(path) do
    path
    |> File.stream!([], 102400)
    |> count
  end

  def count(%File.Stream{} = stream) do
    table = :ets.new(:words, [])
    pattern = :binary.compile_pattern([" ", "\n"])

    stream
    |> Enum.to_list()
    |> :binary.list_to_bin()
    |> String.split(pattern)
    |> Enum.each(fn word -> :ets.update_counter(table, word, {2, 1}, {word, 0}) end)

    :ets.tab2list(table)
  end
end