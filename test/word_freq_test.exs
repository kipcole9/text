defmodule Text.WordFreqTest do
  use ExUnit.Case, async: false
  doctest Text.WordFreq

  alias Text.WordFreq

  test "count/2 returns positive for common words and 0 for unknown" do
    assert WordFreq.count("the") > 1_000_000_000
    assert WordFreq.count("zzzznotaword") == 0
  end

  test "count/2 is case insensitive" do
    assert WordFreq.count("The") == WordFreq.count("the")
    assert WordFreq.count("THE") == WordFreq.count("the")
  end

  test "frequency/2 is normalised" do
    f = WordFreq.frequency("the")
    assert f > 0.0 and f < 1.0
  end

  test "zipf/2 — common words score high, unknown is 0" do
    assert WordFreq.zipf("the") > 6.0
    assert WordFreq.zipf("zzzznotaword") == 0.0
  end

  test "rank/2 — 'the' is most frequent" do
    assert WordFreq.rank("the") == 1
    assert WordFreq.rank("zzzznotaword") == nil
  end

  test "top/2 returns descending order" do
    top10 = WordFreq.top(10)
    assert length(top10) == 10
    counts = Enum.map(top10, fn {_, c} -> c end)
    assert counts == Enum.sort(counts, :desc)
  end

  test "vocabulary_size/1 reflects bundled corpus" do
    assert WordFreq.vocabulary_size() == 30_000
  end

  test "unknown language raises with helpful message" do
    assert_raise ArgumentError, ~r/could not locate/, fn ->
      WordFreq.count("hello", language: :"unloaded-#{System.unique_integer([:positive])}")
    end
  end

  test "language input accepts atom, string, and BCP-47" do
    assert WordFreq.count("the", language: :en) == WordFreq.count("the", language: "en")
    assert WordFreq.count("the", language: "en-US") == WordFreq.count("the", language: :en)
  end
end
