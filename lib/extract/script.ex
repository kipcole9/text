defmodule Text.Extract.Script do
  @moduledoc """
  UTR #39 §5.1 single-script restriction check, used by
  `Text.Extract` to flag mixed-script hosts as potential homograph
  attacks.

  Operates on the Unicode form of an IDN host string. Returns `true`
  if all characters belong to a single script (ignoring `:common`
  and `:inherited`, and treating Han/Hiragana/Katakana as one
  augmented Japanese script per UTR #39 §5.2). Returns `false`
  otherwise — that's the case where `аpple.com` (Cyrillic `а` mixed
  with Latin) would be rejected by `:strict_idn`.

  Implementation delegates to `Unicode.script_dominance/1` from the
  `:unicode` package, which counts script occurrences efficiently.
  """

  @japanese_augmented MapSet.new([:han, :hiragana, :katakana])
  @ignored_scripts MapSet.new([:common, :inherited])

  @doc """
  Returns `true` if `text` uses only a single script (per UTR #39
  §5.1, with the Japanese augmented set in §5.2).

  ### Arguments

  * `text` is a UTF-8 string.

  ### Returns

  * A boolean.

  ### Examples

      iex> Text.Extract.Script.single_script?("paypal.com")
      true

      iex> Text.Extract.Script.single_script?("müller.de")
      true

      # Cyrillic "а"
      iex> Text.Extract.Script.single_script?(<<"а"::utf8>> <> "pple.com")
      false

      iex> Text.Extract.Script.single_script?("漢字ひらがな")
      true

      iex> Text.Extract.Script.single_script?("123")
      true

      iex> Text.Extract.Script.single_script?("")
      true

  """
  @spec single_script?(String.t()) :: boolean()
  def single_script?(text) when is_binary(text) do
    text
    |> Unicode.script()
    |> Enum.reject(&MapSet.member?(@ignored_scripts, &1))
    |> reduce_japanese()
    |> Enum.uniq()
    |> length()
    |> Kernel.<=(1)
  end

  # Han + Hiragana + Katakana are treated as one Japanese augmented
  # script per UTR #39 §5.2. Collapse them to a single tag so the
  # single-script check passes for mixed-Japanese input.
  defp reduce_japanese(scripts) do
    Enum.map(scripts, fn s ->
      if MapSet.member?(@japanese_augmented, s), do: :japanese, else: s
    end)
  end
end
