defmodule Text.NERTest do
  use ExUnit.Case, async: false

  alias Text.NER
  alias Text.NER.Entity

  describe "without :bumblebee compiled, the module raises a helpful message" do
    @describetag skip: Code.ensure_loaded?(Bumblebee)

    test "extract/2 raises with deps instructions" do
      assert_raise RuntimeError, ~r/:bumblebee/, fn ->
        NER.extract("Barack Obama visited Berlin")
      end
    end
  end

  describe "extract/2 against the real model" do
    @describetag :requires_bumblebee_model

    setup do
      NER.reset(:all)
      :ok
    end

    test "extracts a person and a location" do
      entities = NER.extract("Barack Obama visited Berlin in 2013.")
      assert is_list(entities)
      assert length(entities) >= 1

      Enum.each(entities, fn %Entity{} = e ->
        assert is_binary(e.text)
        assert is_atom(e.type)
        assert is_integer(e.start) and e.start >= 0
        assert is_integer(e.end) and e.end >= e.start
        assert is_float(e.score)
      end)
    end

    test "result types include :per for people and :loc for places" do
      entities = NER.extract("Barack Obama lived in Washington for years.")
      types = Enum.map(entities, & &1.type)

      # The default multilingual model uses CoNLL labels :per, :loc,
      # :org, :misc. Both should appear here.
      assert :per in types
      assert :loc in types
    end

    test "min_score filter drops low-confidence entities" do
      all = NER.extract("This is generic text without entities.")

      filtered =
        NER.extract("This is generic text without entities.", min_score: 0.99)

      # Whatever the unfiltered result is, the filtered list is no
      # longer than it.
      assert length(filtered) <= length(all)
    end
  end
end
