defmodule Text.SummarizeTest do
  use ExUnit.Case, async: true
  doctest Text.Summarize

  alias Text.Summarize

  @text """
  Cats are lovely pets and very independent. Many people enjoy keeping cats at home.
  Cats can be playful and curious creatures. Dogs are loyal and friendly companions.
  Goldfish are quiet and easy to care for. Many families with small children prefer goldfish.
  Birds sing beautifully in the morning and bring joy. Reptiles like turtles and lizards are also popular pets.
  """

  test "summarize/2 returns a string of selected sentences" do
    summary = Summarize.summarize(@text, sentences: 2)
    assert is_binary(summary)
    assert summary =~ "."
  end

  test "summarize_sentences/2 returns a list" do
    list = Summarize.summarize_sentences(@text, sentences: 3)
    assert length(list) == 3
    assert Enum.all?(list, &is_binary/1)
  end

  test "request more sentences than exist returns all" do
    short = "Only one sentence."
    assert Summarize.summarize_sentences(short, sentences: 5) == ["Only one sentence."]
  end

  test "lexrank algorithm works" do
    summary = Summarize.summarize(@text, sentences: 2, algorithm: :lexrank)
    assert is_binary(summary)
  end

  test "unknown algorithm raises" do
    assert_raise ArgumentError, fn ->
      Summarize.summarize(@text, algorithm: :unknown)
    end
  end

  test "scores/2 returns one score per sentence in document order" do
    scores = Summarize.scores(@text)
    sentences = Text.Segment.sentences(@text)
    assert length(scores) == length(sentences)
    assert Enum.all?(scores, &is_float/1)
  end

  test "summary preserves original sentence order" do
    summary_list = Summarize.summarize_sentences(@text, sentences: 3)
    sentences = Text.Segment.sentences(@text)

    indices = Enum.map(summary_list, fn s -> Enum.find_index(sentences, &(&1 == s)) end)
    assert indices == Enum.sort(indices)
  end

  test "empty text returns empty result" do
    assert Summarize.summarize_sentences("") == []
  end
end
