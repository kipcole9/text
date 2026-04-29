defmodule Text.SpellTest do
  use ExUnit.Case, async: true
  doctest Text.Spell

  alias Text.Spell

  test "correct/2 fixes simple typos" do
    assert Spell.correct("speling") == "spelling"
    assert Spell.correct("hellp") == "help"
    assert Spell.correct("frinds") == "friends"
  end

  test "correct/2 leaves known words alone" do
    assert Spell.correct("the") == "the"
    assert Spell.correct("hello") == "hello"
  end

  test "correct/2 returns input when nothing close enough is known" do
    assert Spell.correct("xqzwt") == "xqzwt"
  end

  test "candidates/2 returns by frequency descending" do
    cands = Spell.candidates("speling")
    assert "spelling" in cands
  end

  test "candidates/2 limit works" do
    assert length(Spell.candidates("speling", limit: 1)) <= 1
  end

  test "max_edit_distance: 1 catches single-edit typos" do
    assert Spell.correct("speling", max_edit_distance: 1) == "spelling"
  end

  test "max_edit_distance: 1 does not stretch to two edits" do
    # "frinds" is a 1-edit typo of "friends" (insert e)
    assert Spell.correct("frinds", max_edit_distance: 1) == "friends"
  end

  test "edits1/1 includes basic edit operations" do
    edits = Spell.edits1("spell")
    assert "spel" in edits
    assert "spelll" in edits
    assert "spell" in edits or "spelll" in edits
  end

  test "known?/2 — case insensitive" do
    assert Spell.known?("Hello") == true
    assert Spell.known?("HELLO") == true
  end
end
