defmodule Text.PII do
  @moduledoc """
  Pattern-based detection and redaction of personally-identifiable
  information.

  Useful as a sanitisation step before logging text, before sending
  user input to a third-party service, or before training/eval on a
  corpus that may contain accidental PII. The detectors are pure
  regex (with a Luhn check on credit cards) — fast, deterministic,
  and small enough to inspect.

  Pattern coverage is conservative: false positives are minimised
  at the cost of missing unusual formats. For broader recall on
  names, addresses, and other open-class entities, combine this
  with `Text.NER` (which uses a Bumblebee model).

  ### Detected types

  | Type            | What it catches                                          |
  |-----------------|----------------------------------------------------------|
  | `:email`        | RFC-5322-ish email addresses.                            |
  | `:phone`        | International E.164 (`+1234567890`) and common US/EU dashed/parens forms with 7+ digits. |
  | `:credit_card`  | 13–19 digit sequences that pass the Luhn check.          |
  | `:iban`         | IBAN format (country code + 2 check digits + up to 30 alphanumerics). |
  | `:ssn`          | US Social Security numbers `NNN-NN-NNNN`.                |
  | `:ipv4`         | Dotted-quad IP addresses with octets 0–255.              |
  | `:ipv6`         | IPv6 addresses (full and compressed forms).              |
  | `:url`          | `http(s)://` URLs.                                       |

  """

  defp patterns do [
    email: ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/,
    url: ~r{\bhttps?://[^\s<>"']+},
    ssn: ~r/\b\d{3}-\d{2}-\d{4}\b/,
    iban: ~r/\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b/,
    ipv4: ~r/\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d?\d)\b/,
    ipv6:
      ~r/\b(?:[A-Fa-f0-9]{1,4}:){7}[A-Fa-f0-9]{1,4}\b|\b(?:[A-Fa-f0-9]{1,4}:){1,7}:|\b:(?::[A-Fa-f0-9]{1,4}){1,7}\b/,
    phone:
      ~r/\+?\d{1,3}[\s\-.]?\(?\d{2,4}\)?[\s\-.]?\d{3,4}[\s\-.]?\d{3,4}\b|\b\(?\d{3}\)?[\s\-.]?\d{3}[\s\-.]?\d{4}\b/,
    # Credit-card candidate: 13-19 contiguous digits, optionally separated by spaces or dashes.
    # Always re-validated by Luhn before being reported.
    credit_card: ~r/\b(?:\d[ \-]?){12,18}\d\b/
  ]
  end

  @doc """
  Returns the list of detector type atoms supported by this module.
  """
  @spec types() :: [atom()]
  def types, do: Keyword.keys(patterns())

  @doc """
  Detects PII matches in the text.

  ### Arguments

  * `text` is the input string.

  ### Options

  * `:types` is the list of detector types to run. Default is all
    types from `types/0`. Pass `[:email, :phone]` to limit detection.

  ### Returns

  * A list of maps `%{type: atom, value: String.t(), start: integer, length: integer}`
    sorted by `:start`. The `:start` is a byte offset, suitable for
    `String.slice/3`. Credit-card matches are filtered to only those
    that pass the Luhn check.

  ### Examples

      iex> [m] = Text.PII.detect("contact me at alice@example.com please")
      iex> {m.type, m.value}
      {:email, "alice@example.com"}

      iex> Text.PII.detect("nothing here")
      []

  """
  @spec detect(String.t(), keyword()) :: [
          %{type: atom(), value: String.t(), start: non_neg_integer(), length: pos_integer()}
        ]
  def detect(text, options \\ []) when is_binary(text) do
    requested = Keyword.get(options, :types, types())

    patterns()
    |> Enum.filter(fn {type, _} -> type in requested end)
    |> Enum.flat_map(fn {type, regex} ->
      Regex.scan(regex, text, return: :index)
      |> Enum.map(fn [{start, len}] ->
        value = binary_part(text, start, len)
        %{type: type, value: value, start: start, length: len}
      end)
      |> Enum.filter(&keep_match?(&1, type))
    end)
    |> dedup_overlaps()
    |> Enum.sort_by(& &1.start)
  end

  @doc """
  Replaces every detected PII match with a redaction placeholder.

  ### Arguments

  * `text` is the input string.

  ### Options

  * `:types` — same as `detect/2`.

  * `:placeholder` — either a string (used for every match) or a
    function `(type :: atom -> String.t())` returning the
    placeholder for each match type. The default is
    `fn type -> "[" <> String.upcase(to_string(type)) <> "]" end`.

  ### Returns

  * The text with every detected match replaced by the configured
    placeholder. If matches overlap, the earlier-starting match wins.

  ### Examples

      iex> Text.PII.redact("email me at alice@example.com")
      "email me at [EMAIL]"

      iex> Text.PII.redact("phone +1-555-123-4567 email alice@x.io",
      ...>   placeholder: fn _ -> "***" end)
      "phone *** email ***"

  """
  @spec redact(String.t(), keyword()) :: String.t()
  def redact(text, options \\ []) when is_binary(text) do
    placeholder_fun = build_placeholder(Keyword.get(options, :placeholder))
    matches = detect(text, options)

    matches
    |> Enum.reverse()
    |> Enum.reduce(text, fn %{type: type, start: s, length: l}, acc ->
      <<head::binary-size(^s), _::binary-size(^l), tail::binary>> = acc
      head <> placeholder_fun.(type) <> tail
    end)
  end

  defp build_placeholder(nil), do: fn type -> "[#{String.upcase(to_string(type))}]" end
  defp build_placeholder(str) when is_binary(str), do: fn _ -> str end
  defp build_placeholder(fun) when is_function(fun, 1), do: fun

  defp keep_match?(%{value: value}, :credit_card), do: luhn_valid?(value)
  defp keep_match?(_match, _type), do: true

  # If two matches overlap, keep the one that starts earlier; on a tie,
  # keep the longer one.
  defp dedup_overlaps(matches) do
    matches
    |> Enum.sort_by(fn m -> {m.start, -m.length} end)
    |> Enum.reduce([], fn m, acc ->
      case acc do
        [last | _] when last.start + last.length > m.start -> acc
        _ -> [m | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp luhn_valid?(string) do
    digits =
      string
      |> String.replace(~r/[^0-9]/, "")
      |> String.to_charlist()
      |> Enum.map(&(&1 - ?0))

    case length(digits) do
      n when n >= 13 and n <= 19 -> luhn_sum(Enum.reverse(digits), 0, 0) |> rem(10) == 0
      _ -> false
    end
  end

  defp luhn_sum([], _idx, sum), do: sum

  defp luhn_sum([d | rest], idx, sum) do
    contribution =
      if rem(idx, 2) == 1 do
        doubled = d * 2
        if doubled > 9, do: doubled - 9, else: doubled
      else
        d
      end

    luhn_sum(rest, idx + 1, sum + contribution)
  end
end
