defmodule Text.DataTest do
  use ExUnit.Case, async: false
  doctest Text.Data

  alias Text.Data

  describe "data_dir/0" do
    test "expands the configured directory" do
      Application.put_env(:text, :data_dir, "~/test-cache")
      assert Data.data_dir() == Path.expand("~/test-cache")
    after
      Application.delete_env(:text, :data_dir)
    end

    test "defaults to ~/.cache/text" do
      Application.delete_env(:text, :data_dir)
      assert Data.data_dir() == Path.expand("~/.cache/text")
    end
  end

  describe "auto_download?/1" do
    test "defaults to false" do
      Application.delete_env(:text, :auto_download_test_domain_data)
      assert Data.auto_download?(:test_domain) == false
    end

    test "honours configured value" do
      Application.put_env(:text, :auto_download_test_domain_data, true)
      assert Data.auto_download?(:test_domain) == true
    after
      Application.delete_env(:text, :auto_download_test_domain_data)
    end
  end

  describe "fetch/3" do
    test "returns the bundled file when present" do
      assert {:ok, path} = Data.fetch(:hyphenation, "hyph-en-us.tex")
      assert File.exists?(path)
    end

    test "missing file with no URL returns helpful ArgumentError" do
      assert {:error, %ArgumentError{message: msg}} =
               Data.fetch(:hyphenation, "no-such-file.tex")

      assert msg =~ "could not locate"
      assert msg =~ "no-such-file.tex"
    end

    test "missing file with URL but auto-download off mentions the config key" do
      Application.delete_env(:text, :auto_download_hyphenation_data)

      assert {:error, %ArgumentError{message: msg}} =
               Data.fetch(:hyphenation, "no-such-file.tex", url: "https://example.com/x.tex")

      assert msg =~ "auto_download_hyphenation_data"
      assert msg =~ "https://example.com/x.tex"
    end
  end

  describe "cache_path/2 and bundled_path/2" do
    test "compose paths under the configured directories" do
      assert Data.cache_path(:foo, "bar.tsv") |> Path.basename() == "bar.tsv"
      assert Data.bundled_path(:foo, "bar.tsv") |> Path.basename() == "bar.tsv"
    end
  end
end
