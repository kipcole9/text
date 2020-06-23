defmodule Text.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :text,
      version: @version,
      docs: docs(),
      elixir: "~> 1.8",
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
      extras: ["README.md", "CHANGELOG.md", "LICENSE.md"]
    ]
  end

  defp deps do
    [
      {:flow, "~> 0.14"},
      {:sweet_xml, "~> 0.6", only: [:dev, :test], optional: true},
      {:meeseeks, "~> 0.15.1", only: [:dev, :test], optional: true},
      {:ex_doc, "~> 0.21", only: [:dev, :release], optional: true},
      {:benchee, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/kipcole9/text",
      "Readme" => "https://github.com/kipcole9/text/blob/v#{@version}/README.md",
      "Changelog" => "https://github.com/kipcole9/text/blob/v#{@version}/CHANGELOG.md"
    }
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "test"]
  defp elixirc_paths(:dev), do: ["lib", "mix", "bench"]
  defp elixirc_paths(_), do: ["lib"]
end
