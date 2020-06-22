defmodule Text.Ngram do
  @moduledoc """
  Compute ngrams and their counts from a given
  UTF8 string.

  Computes ngrams for n in 2..7

  """
  @max_ngram 7
  @min_ngram 2
  @default_ngram @min_ngram

  @type ngram_range :: 2..7
  @spec ngram(String.t(), ngram_range) :: %{list() => integer}

  defmodule Frequency do
    defstruct [
      :rank,
      :count,
      :frequency,
      :log_frequency,
      :global_rank,
      :global_frequency
    ]
  end

  @doc """
  Returns a map of n-grams for a given text
  and n-gram size.

  The n-gram size is a minimum of #{@min_ngram} and
  a maximum of #{@max_ngram} with a default of #{@default_ngram}.

  """
  def ngram(string, n \\ @default_ngram) when is_binary(string) and n in @min_ngram..@max_ngram do
    string
    |> :unicode.characters_to_nfc_binary()
    |> ngram(n, %{})
  end

  def ngram("", _n, acc) do
    acc
  end

  def ngram(<<_a::utf8>>, 2, acc) do
    acc
  end

  def ngram(<<_a::utf8, _b::utf8>>, 3, acc) do
    acc
  end

  def ngram(<<_a::utf8, _b::utf8, _c::utf8>>, 4, acc) do
    acc
  end

  def ngram(<<_a::utf8, _b::utf8, _c::utf8, _d::utf8>>, 5, acc) do
    acc
  end

  def ngram(<<_a::utf8, _b::utf8, _c::utf8, _d::utf8, _e::utf8>>, 6, acc) do
    acc
  end

  def ngram(<<_a::utf8, _b::utf8, _c::utf8, _d::utf8, _e::utf8, _f::utf8>>, 7, acc) do
    acc
  end

  def ngram(<<a::utf8, b::utf8, rest::binary>>, 2 = n, acc) do
    ngram = [a, b]
    acc = Map.update(acc, ngram, 1, &(&1 + 1))
    ngram(<<b::utf8, rest::binary>>, n, acc)
  end

  def ngram(<<a::utf8, b::utf8, c::utf8, rest::binary>>, 3 = n, acc) do
    ngram = [a, b, c]
    acc = Map.update(acc, ngram, 1, &(&1 + 1))
    ngram(<<b::utf8, c::utf8, rest::binary>>, n, acc)
  end

  def ngram(<<a::utf8, b::utf8, c::utf8, d::utf8, rest::binary>>, 4 = n, acc) do
    ngram = [a, b, c, d]
    acc = Map.update(acc, ngram, 1, &(&1 + 1))
    ngram(<<b::utf8, c::utf8, d::utf8, rest::binary>>, n, acc)
  end

  def ngram(<<a::utf8, b::utf8, c::utf8, d::utf8, e::utf8, rest::binary>>, 5 = n, acc) do
    ngram = [a, b, c, d, e]
    acc = Map.update(acc, ngram, 1, &(&1 + 1))
    ngram(<<b::utf8, c::utf8, d::utf8, e::utf8, rest::binary>>, n, acc)
  end

  def ngram(<<a::utf8, b::utf8, c::utf8, d::utf8, e::utf8, f::utf8, rest::binary>>, 6 = n, acc) do
    ngram = [a, b, c, d, e, f]
    acc = Map.update(acc, ngram, 1, &(&1 + 1))
    ngram(<<b::utf8, c::utf8, d::utf8, e::utf8, f::utf8, rest::binary>>, n, acc)
  end

  def ngram(
        <<a::utf8, b::utf8, c::utf8, d::utf8, e::utf8, f::utf8, g::utf8, rest::binary>>,
        7 = n,
        acc
      ) do
    ngram = [a, b, c, d, e, f, g]
    acc = Map.update(acc, ngram, 1, &(&1 + 1))
    ngram(<<b::utf8, c::utf8, d::utf8, e::utf8, f::utf8, g::utf8, rest::binary>>, n, acc)
  end
end
