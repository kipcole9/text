defmodule Text.MixProject do
  use Mix.Project

  @version "0.3.0-dev"

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
      licenses: ["Apache 2.0"],
      links: links(),
      files: [
        "lib",
        "priv",
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
      skip_undefined_reference_warnings_on: ["changelog", "CHANGELOG.md"],
      extras: ["README.md", "CHANGELOG.md", "LICENSE.md"]
    ]
  end

  defp deps do
    base() ++ runtime_optional_deps()
  end

  defp base do
    [
      {:flow, "~> 0.14 or ~> 1.0"},
      {:nx, "~> 0.9 or ~> 0.10"},
      {:unicode, "~> 1.21"},
      {:unicode_transform, "~> 1.0"},
      {:unicode_string, "~> 2.0"},
      {:ex_doc, "~> 0.21 or ~> 0.30", only: [:dev, :release], optional: true},
      {:benchee, "~> 1.0", only: :dev, runtime: false},
      {:jason, "~> 1.2"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false, optional: true}
    ]
  end

  # Runtime-relevant optional deps. Set the `TEXT_SKIP_OPTIONAL_DEPS=1`
  # env var to omit these — used by the "without optional deps" CI job
  # to verify the package compiles and tests pass without them, exercising
  # the `Code.ensure_loaded?(Bumblebee)` etc. fallbacks.
  defp runtime_optional_deps do
    if System.get_env("TEXT_SKIP_OPTIONAL_DEPS") == "1" do
      []
    else
      [
        {:exla, "~> 0.9 or ~> 0.10", optional: true},
        {:bumblebee, "~> 0.6", optional: true},
        {:localize, "~> 0.23", optional: true}
      ]
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
