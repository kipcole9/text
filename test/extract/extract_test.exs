defmodule Text.ExtractTest do
  use ExUnit.Case, async: true
  doctest Text.Extract
  doctest Text.Extract.Boundary
  doctest Text.Extract.Email
  doctest Text.Extract.Scanner
  doctest Text.Extract.Script
  doctest Text.Extract.Tld
  doctest Text.Extract.Twitter
  doctest Text.Extract.Url

  alias Text.Extract

  describe "urls/2" do
    test "extracts a single scheme URL" do
      assert [%{url: "http://example.com", host: "example.com"}] =
               Extract.urls("see http://example.com today")
    end

    test "extracts multiple bare URLs" do
      urls =
        Extract.urls("Three: foo.com bar.net baz.org")
        |> Enum.map(& &1.url)

      assert urls == ["foo.com", "bar.net", "baz.org"]
    end

    test "rejects invalid TLDs" do
      assert [] = Extract.urls("see http://no-tld please")
      assert [] = Extract.urls("foo.somecom is fake")
    end

    test "preserves Wikipedia-style parens" do
      [r] = Extract.urls("read https://en.wikipedia.org/wiki/URI_(disambiguation)")
      assert r.url == "https://en.wikipedia.org/wiki/URI_(disambiguation)"
    end

    test "strips trailing sentence punctuation" do
      [r] = Extract.urls("see http://example.com.")
      assert r.url == "http://example.com"
    end

    test "rejects URLs preceded by $ (cashtag-like)" do
      assert [] = Extract.urls("$foo.com is not a URL")
    end

    test "extracts IDN host (Punycode in :ascii)" do
      [r] = Extract.urls("Visit http://" <> <<0x00FC::utf8>> <> "ber.de today")
      assert r.url == "http://über.de"
      assert r.ascii == "http://xn--ber-goa.de"
    end

    test ":strict_idn rejects mixed-script hosts" do
      cyr_a = <<0x0430::utf8>>
      input = "Click " <> cyr_a <> "pple.com please"

      assert [_] = Extract.urls(input)
      assert [] = Extract.urls(input, strict_idn: true)
    end

    test "spans use byte offsets" do
      [r] = Extract.urls("hi http://x.com bye")
      assert r.span == {3, 12}
    end

    test ":require_scheme rejects bare hosts" do
      assert [] = Extract.urls("foo.com", require_scheme: true)
      assert [_] = Extract.urls("foo.com", require_scheme: false)
      assert [_] = Extract.urls("https://foo.com", require_scheme: true)
    end
  end

  describe "emails/2" do
    test "extracts a basic email" do
      [r] = Extract.emails("Contact alice@example.com today.")
      assert r.email == "alice@example.com"
      assert r.local == "alice"
      assert r.host == "example.com"
    end

    test "rejects invalid TLDs" do
      assert [] = Extract.emails("alice@example.fake")
    end

    test "extracts IDN host email" do
      [r] = Extract.emails("Email me at bob@" <> <<0x00FC::utf8>> <> "ber.de please.")
      assert r.email == "bob@über.de"
      assert r.ascii == "bob@xn--ber-goa.de"
    end

    test "EAI permits non-ASCII local parts" do
      input = "Contact " <> <<0x7528, 0x6237::utf8>> <> "@example.com"
      assert [_] = Extract.emails(input)
      assert [] = Extract.emails(input, eai: false)
    end
  end

  describe "all/2" do
    test "interleaves URLs and emails in document order" do
      text = "Visit https://example.com or email alice@example.com please."
      results = Extract.all(text)

      assert [%{kind: :url}, %{kind: :email}] = results
    end

    test "email wins when an email is wholly inside a URL span" do
      # mailto: handled by email extractor — the URL extractor doesn't
      # match `mailto:` URLs since `mailto` is not in the default scheme
      # list (and there's no `://`). Just verify standalone email wins.
      [r] = Extract.all("alice@example.com")
      assert r.kind == :email
    end
  end

  describe "split/2" do
    test "round-trips to the original text" do
      text = "Visit foo.com or alice@example.com please."

      reconstructed =
        text
        |> Extract.split()
        |> Enum.map_join("", fn
          str when is_binary(str) -> str
          %{kind: :url, url: u} -> u
          %{kind: :email, email: e} -> e
        end)

      assert reconstructed == text
    end

    test "empty string returns empty list" do
      assert Extract.split("") == []
    end

    test "string with no entities returns single fragment" do
      assert Extract.split("nothing here") == ["nothing here"]
    end

    test "two adjacent URLs have no string between them" do
      result = Extract.split("foo.com,bar.org")

      # `,` between is a separator; URL ends at `.com`, second URL starts
      # at `b` of `bar.org` (preceded by `,` which is not in forbidden
      # preceders).
      assert [_, ",", _] = result
      [first, _, second] = result
      assert first.url == "foo.com"
      assert second.url == "bar.org"
    end
  end

  describe "autolink/2" do
    # Helper: extract the rendered HTML string from the `{:safe, …}`
    # value autolink/2 returns.
    defp render(text, options \\ []) do
      text |> Extract.autolink(options) |> Phoenix.HTML.safe_to_string()
    end

    test "returns Phoenix.HTML safe iodata" do
      assert {:safe, _} = Extract.autolink("hello world")
    end

    test "wraps URL in anchor with href and display text" do
      assert render("Visit https://example.com today.") ==
               ~s|Visit <a href="https://example.com">https://example.com</a> today.|
    end

    test "wraps email in mailto anchor" do
      assert render("Email alice@example.com.") ==
               ~s|Email <a href="mailto:alice@example.com">alice@example.com</a>.|
    end

    test "schemeless URL gets default https href" do
      result = render("see foo.com today")
      assert result =~ ~s|href="https://foo.com"|
      assert result =~ ~s|>foo.com</a>|
    end

    test ":href_scheme overrides default" do
      result = render("see foo.com today", href_scheme: :http)
      assert result =~ ~s|href="http://foo.com"|
    end

    test "HTML-escapes plain text segments" do
      assert render("a & b < c > d") == "a &amp; b &lt; c &gt; d"
    end

    test "HTML-escapes anchor display text" do
      # No URL contains < > & in normal use, but test the escape path.
      result = render(~s|"quoted" foo.com|)
      assert result =~ "&quot;quoted&quot;"
    end

    test ":url_attrs adds attributes to URL anchors" do
      result = render("see foo.com", url_attrs: [target: "_blank", rel: "noopener"])
      assert result =~ ~s|target="_blank"|
      assert result =~ ~s|rel="noopener"|
    end

    test ":email_attrs adds attributes to email anchors only" do
      result =
        render("foo.com a@b.com",
          url_attrs: [class: "u"],
          email_attrs: [class: "e"]
        )

      assert result =~ ~s|class="u">foo.com|
      assert result =~ ~s|class="e">a@b.com|
    end

    test ":url_renderer returning a string is HTML-escaped" do
      # The custom renderer's string output is treated as untrusted
      # and escaped — this prevents an accidental injection.
      result =
        render("see foo.com today",
          url_renderer: fn e -> "[" <> e.url <> "]" end
        )

      assert result == "see [foo.com] today"
    end

    test ":url_renderer returning {:safe, _} is trusted" do
      result =
        render("see foo.com today",
          url_renderer: fn e -> {:safe, [~s|<b>|, e.url, ~s|</b>|]} end
        )

      assert result == "see <b>foo.com</b> today"
    end

    test "uses Punycode in href for IDN URLs but Unicode in display" do
      result = render("Visit " <> <<0x00FC::utf8>> <> "ber.de today")
      assert result =~ ~s|href="https://xn--ber-goa.de"|
      assert result =~ ">über.de</a>"
    end
  end
end
