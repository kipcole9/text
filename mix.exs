defmodule Text.MixProject do
  use Mix.Project

  @version "0.6.2"

  def project do
    [
      app: :text,
      version: @version,
      docs: docs(),
      elixir: "~> 1.17",
      name: "Text",
      source_url: "https://github.com/kipcole9/text",
      description: description(),
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore_warnings",
        plt_add_apps: ~w(inets jason mix)a
      ]
    ]
  end

  defp description do
    """
    Text analysis and processing for Elixir including ngram,
    language detection and more.
    """
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      files: [
        "lib",
        # Ship only the priv subdirs that contain compile-time
        # `@external_resource` data; deliberately exclude `priv/lid_176`
        # (the 125 MB model is a user-downloaded runtime asset, fetched
        # via `mix text.download_lid176`) and `priv/scripts` (dev-only
        # fixture generators).
        "priv/emoji_sentiment",
        "priv/extract",
        "priv/hyphenation",
        "priv/inflection",
        "priv/lemma",
        "priv/readability",
        "priv/sentiment",
        "priv/stopwords",
        "priv/wordfreq",
        "guides",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      logo: "logo.png",
      formatters: ["html", "markdown"],
      skip_undefined_reference_warnings_on: [
        "changelog",
        "CHANGELOG.md",
        "README.md"
      ],
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE.md",
        "guides/text_classification.md",
        "guides/sentiment.md",
        "guides/pos_ner.md",
        "guides/kwic.md",
        "guides/word_clouds.md"
      ],
      groups_for_extras: [
        Guides: ~r"guides/.*"
      ],
      assets: %{"guides/word_clouds_assets" => "word_clouds_assets"}
    ]
  end

  defp deps do
    base() ++ runtime_optional_deps()
  end

  defp base do
    [
      {:flow, "~> 0.14 or ~> 1.0"},
      {:nx, "~> 0.9 or ~> 0.10"},
      {:unicode, "~> 1.22"},
      {:unicode_idna, "~> 0.1"},
      {:unicode_transform, "~> 1.0"},
      {:unicode_string, "~> 2.1"},
      {:phoenix_html, "~> 4.0"},
      {:ex_doc, "~> 0.21 or ~> 0.30", only: [:dev, :release], optional: true},
      {:benchee, "~> 1.0", only: :dev, runtime: false},
      {:yaml_elixir, "~> 2.9", only: [:test], runtime: false},
      {:jason, "~> 1.2"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false, optional: true}
    ] ++ maybe_json_polyfill()
  end

  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0"}]
    end
  end

  # Runtime-relevant optional deps. CI uses two sets of env vars:
  #
  # * `TEXT_SKIP_OPTIONAL_DEPS=1` — skip every optional dep. Verifies
  #   the package compiles and tests pass with all `Code.ensure_loaded?`
  #   fallbacks active.
  #
  # * `TEXT_SKIP_<DEP>=1` — per-dep granular skips. Useful for
  #   reproducing a specific consumer setup (e.g. `TEXT_SKIP_BUMBLEBEE=1`
  #   simulates installs that don't want the heavy ML stack).
  #
  # Recognised per-dep flags: `TEXT_SKIP_EXLA`, `TEXT_SKIP_BUMBLEBEE`,
  # `TEXT_SKIP_LOCALIZE`, `TEXT_SKIP_COLOR`.
  # Mix dep tuples come in two shapes: `{name, requirement, opts}` for
  # Hex deps and `{name, opts}` for path/git deps. Both carry our
  # private `:skip` key in `opts`; extract it uniformly.
  defp dep_skipped?({_name, _req, opts}), do: System.get_env(opts[:skip]) == "1"
  defp dep_skipped?({_name, opts}), do: System.get_env(opts[:skip]) == "1"

  defp strip_skip_key({name, req, opts}), do: {name, req, Keyword.delete(opts, :skip)}
  defp strip_skip_key({name, opts}), do: {name, Keyword.delete(opts, :skip)}

  defp runtime_optional_deps do
    if System.get_env("TEXT_SKIP_OPTIONAL_DEPS") == "1" do
      []
    else
      [
        {:exla, "~> 0.9 or ~> 0.10", optional: true, skip: "TEXT_SKIP_EXLA"},
        {:bumblebee, "~> 0.6", optional: true, skip: "TEXT_SKIP_BUMBLEBEE"},
        {:localize, "~> 0.23", optional: true, skip: "TEXT_SKIP_LOCALIZE"},
        {:color, "~> 0.12", optional: true, skip: "TEXT_SKIP_COLOR"},
        {:text_stemmer, "~> 0.1", optional: true, skip: "TEXT_SKIP_TEXT_STEMMER"}
      ]
      |> Enum.reject(&dep_skipped?/1)
      |> Enum.map(&strip_skip_key/1)
    end
  end

  def links do
    %{
      "GitHub" => "https://github.com/kipcole9/text",
      "Readme" => "https://github.com/kipcole9/text/blob/v#{@version}/README.md",
      "Changelog" => "https://github.com/kipcole9/text/blob/v#{@version}/CHANGELOG.md"
    }
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "bench"]
  defp elixirc_paths(_), do: ["lib"]
end
