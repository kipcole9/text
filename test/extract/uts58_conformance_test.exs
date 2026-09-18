defmodule Text.Extract.UTS58ConformanceTest do
  @moduledoc """
  Runs the vendored [UTS #58](https://www.unicode.org/reports/tr58/) conformance suites.

  Refresh the fixtures with `mix text.download_uts58`.

  Both suites pass in full: 344 of 344 detection cases, and 55 of 55 formatting cases given the
  structure each one declares. Termination is additionally checked on its own, since UTS #58 §3.2
  puts the *start* of a link outside its scope and only `Text.Extract.Link` implements what the
  specification actually defines.
  """

  use ExUnit.Case, async: true

  alias Text.Extract.Escape
  alias Text.UTS58.Conformance

  describe "link detection (UTS #58 §3.5.1)" do
    test "every detection case passes end to end" do
      failing = Enum.reject(Conformance.detection_cases(), &detects_correctly?/1)

      assert failing == []
    end

    test "termination alone is conformant" do
      # Narrower than the case above and worth keeping separate: every link the specification says
      # exists must survive `shrink/1` unchanged, independently of whether the scanner found it.
      offenders =
        Conformance.detection_cases()
        |> Enum.flat_map(fn {_text, expected} -> expected end)
        |> Enum.reject(&(Text.Extract.Link.shrink(&1) == &1))

      assert offenders == []
    end

    test "no detected link contains a hard terminator" do
      offenders =
        Conformance.detection_cases()
        |> Enum.flat_map(fn {text, _expected} -> Text.Extract.all(text) end)
        |> Enum.filter(fn %{span: {offset, length}} = record ->
          _ = offset
          _ = length

          (record[:url] || record[:email])
          |> String.to_charlist()
          |> Enum.any?(&(Unicode.LinkTerm.link_term(&1) == :hard))
        end)

      assert offenders == []
    end
  end

  describe "minimal escaping (UTS #58 §4.1)" do
    test "every formatting case passes when the structure is known" do
      failing =
        Conformance.formatting_structures()
        |> Enum.reject(fn {parts, minimal} -> Escape.minimal(parts) == minimal end)

      assert failing == []
    end

    test "the string form matches wherever the serialisation is unambiguous" do
      # `minimal/1` on a string cannot recover structure the string does not carry: the fixture
      # writes `{𝑷=α#β}` as `…/%CE%B1#%CE%B2`, whose literal `#` is indistinguishable from the start
      # of a fragment. Those five cases are why `minimal/1` also accepts parsed parts.
      passing =
        Conformance.formatting_cases()
        |> Enum.count(fn {escaped, minimal} -> Escape.minimal(escaped) == minimal end)

      assert passing == 50
    end

    test "the result always survives round-tripping through link detection" do
      # Whatever minimal escaping emits must come back unchanged from the termination algorithm,
      # including for the five cases whose exact output needs structure the string does not carry.
      offenders =
        Conformance.formatting_cases()
        |> Enum.map(fn {escaped, _minimal} -> Escape.minimal(escaped) end)
        |> Enum.reject(&(Text.Extract.Link.shrink(&1) == &1))

      assert offenders == []
    end

    test "non-ASCII is always unescaped and terminators never are" do
      for {parts, _minimal} <- Conformance.formatting_structures() do
        result = Escape.minimal(parts)

        refute String.contains?(result, "%CE"), "left a Greek letter escaped in #{result}"

        refute result
               |> String.to_charlist()
               |> Enum.any?(&(Unicode.LinkTerm.link_term(&1) == :hard)),
               "left a hard terminator unescaped in #{result}"
      end
    end
  end

  defp detects_correctly?({text, expected}) do
    {open, close} = Conformance.markers()

    spans =
      text
      |> Text.Extract.all()
      |> Enum.map(fn %{span: {offset, length}} -> {offset, length} end)
      |> Enum.sort()

    actual = Conformance.insert_markers(text, spans)

    wanted =
      Enum.reduce(expected, text, fn link, acc ->
        String.replace(acc, link, open <> link <> close, global: false)
      end)

    actual == wanted
  end
end
