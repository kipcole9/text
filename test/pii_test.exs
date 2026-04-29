defmodule Text.PIITest do
  use ExUnit.Case, async: true
  doctest Text.PII

  alias Text.PII

  describe "detect/2" do
    test "email" do
      [m] = PII.detect("contact alice@example.com")
      assert m.type == :email
      assert m.value == "alice@example.com"
    end

    test "url" do
      [m] = PII.detect("see https://example.com/path?q=1 thanks")
      assert m.type == :url
      assert m.value == "https://example.com/path?q=1"
    end

    test "ssn" do
      [m] = PII.detect("ssn: 123-45-6789")
      assert m.type == :ssn
    end

    test "ipv4" do
      [m] = PII.detect("server at 192.168.1.1 ok")
      assert m.type == :ipv4
      assert m.value == "192.168.1.1"
    end

    test "credit card with valid Luhn" do
      [m] = PII.detect("card 4532015112830366 here", types: [:credit_card])
      assert m.type == :credit_card
    end

    test "credit card invalid Luhn is rejected" do
      assert PII.detect("card 1234567890123456 here", types: [:credit_card]) == []
    end

    test "phone" do
      [m | _] = PII.detect("call +1-555-123-4567 today")
      assert m.type == :phone
    end

    test "types option limits detection" do
      assert PII.detect("alice@example.com 123-45-6789", types: [:email]) |> length() == 1
    end

    test "no PII returns empty list" do
      assert PII.detect("plain text") == []
    end

    test "multiple matches sorted by start" do
      matches = PII.detect("a@b.com then 123-45-6789")
      assert Enum.map(matches, & &1.type) == [:email, :ssn]
    end
  end

  describe "redact/2" do
    test "default placeholder by type" do
      assert PII.redact("hi alice@example.com") == "hi [EMAIL]"
    end

    test "string placeholder" do
      assert PII.redact("hi alice@example.com", placeholder: "***") == "hi ***"
    end

    test "function placeholder" do
      result =
        PII.redact("hi alice@example.com",
          placeholder: fn t -> "<#{t}>" end
        )

      assert result == "hi <email>"
    end

    test "leaves clean text alone" do
      assert PII.redact("plain text") == "plain text"
    end

    test "redacts multiple matches" do
      assert PII.redact("a@b.com 123-45-6789") == "[EMAIL] [SSN]"
    end
  end

  describe "types/0" do
    test "lists supported types" do
      assert :email in PII.types()
      assert :phone in PII.types()
    end
  end
end
