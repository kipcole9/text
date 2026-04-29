defmodule Text.TruecaseTest do
  use ExUnit.Case, async: false
  doctest Text.Truecase

  alias Text.Truecase

  test "capitalizes sentence starts" do
    assert Truecase.truecase("hello world.") == "Hello world."
    assert Truecase.truecase("hello. world.") == "Hello. World."
  end

  test "applies lexicon to proper nouns" do
    assert Truecase.truecase("london is in england.") == "London is in England."
  end

  test "applies lexicon to acronyms" do
    assert Truecase.truecase("call the fbi.") == "Call the FBI."
  end

  test "applies lexicon to brand names" do
    assert Truecase.truecase("buy an iphone from apple.") == "Buy an iPhone from Apple."
  end

  test "leaves unknown words alone" do
    assert Truecase.truecase("foo bar baz.") == "Foo bar baz."
  end

  test "capitalize_sentences: false skips sentence-start handling" do
    assert Truecase.truecase("hello london.", capitalize_sentences: false) == "hello London."
  end

  test "add_terms/1 extends the lexicon" do
    assert Truecase.truecase("the widgetx api was launched.") ==
             "The widgetx API was launched."

    Truecase.add_terms(%{"widgetx" => "WidgetX"})

    assert Truecase.truecase("the widgetx api was launched.") ==
             "The WidgetX API was launched."
  end
end
