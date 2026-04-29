defmodule Text.LemmaTest do
  use ExUnit.Case, async: true
  doctest Text.Lemma

  alias Text.Lemma

  test "common English inflections" do
    assert Lemma.lemmatize("running") == "run"
    assert Lemma.lemmatize("ran") == "run"
    assert Lemma.lemmatize("runs") == "run"
    assert Lemma.lemmatize("cats") == "cat"
    assert Lemma.lemmatize("mice") == "mouse"
  end

  test "case-insensitive lookup" do
    assert Lemma.lemmatize("Running") == "run"
    assert Lemma.lemmatize("RUNNING") == "run"
  end

  test "unknown words return unchanged" do
    assert Lemma.lemmatize("xyznotaword") == "xyznotaword"
    assert Lemma.lemmatize("zzzzzzz") == "zzzzzzz"
  end

  test "lemmatize_text preserves whitespace and punctuation" do
    assert Lemma.lemmatize_text("the cats are running fast.") == "the cat be run fast."
  end

  test "known?/2" do
    assert Lemma.known?("running") == true
    assert Lemma.known?("xyznotaword") == false
  end

  test "unknown language raises with config hint when auto-download disabled" do
    Application.delete_env(:text, :auto_download_lemma_data)

    assert_raise ArgumentError, ~r/auto_download_lemma_data/, fn ->
      Lemma.lemmatize("hello", language: :"unloaded-#{System.unique_integer([:positive])}")
    end
  end

  test "language input accepts atom, string, and BCP-47" do
    assert Lemma.lemmatize("running", language: :en) == "run"
    assert Lemma.lemmatize("running", language: "en") == "run"
    assert Lemma.lemmatize("running", language: "en-US") == "run"
  end
end
