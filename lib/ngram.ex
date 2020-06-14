defmodule Text.Ngram do
  @moduledoc """
  Compute ngrams and their counts from a given UTF8 string.

  Computes ngrams for n in 2..4

  """

  @spec ngram(String.t(), 2..4) :: %{list() => integer}

  def ngram(string, n \\ 2) when is_binary(string) and n in 2..4 do
    string
    |> String.normalize(:nfc)
    |> ngram(n, %{})
  end

  def ngram("", _n, acc) do
    acc
  end

  def ngram(<< _a :: utf8 >>, 2, acc) do
    acc
  end

  def ngram(<< _a :: utf8, _b :: utf8 >>, 3, acc) do
    acc
  end

  def ngram(<< _a :: utf8, _b :: utf8, _c :: utf8 >>, 4, acc) do
    acc
  end

  def ngram(<< a :: utf8, b :: utf8, rest :: binary >>, 2 = n, acc) do
    acc = update_in(acc, [[a, b]], &(if is_nil(&1), do: 1, else: &1 + 1))
    ngram(<< b :: utf8,rest :: binary >>, n, acc)
  end

  def ngram(<< a :: utf8, b :: utf8, c :: utf8, rest :: binary >>, 3 = n, acc) do
    acc = update_in(acc, [[a, b, c]], &(if is_nil(&1), do: 1, else: &1 + 1))
    ngram(<< b :: utf8, c :: utf8, rest :: binary >>, n, acc)
  end

  def ngram(<< a :: utf8, b :: utf8, c :: utf8, d :: utf8, rest :: binary >>, 4 = n, acc) do
    acc = update_in(acc, [[a, b, c, d]], &(if is_nil(&1), do: 1, else: &1 + 1))
    ngram(<< b :: utf8, c :: utf8, d :: utf8, rest :: binary >>, n, acc)
  end
end
