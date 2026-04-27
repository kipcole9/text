defmodule Text.Sentiment.Backend do
  @moduledoc """
  Behaviour for sentiment-analysis backends.

  Two backends are shipped with `text`:

  * `Text.Sentiment.Backends.Lexicon` (default) — fast, deterministic,
    multilingual lexicon-based scoring. Always available.

  * `Text.Sentiment.Backends.Bumblebee` (optional) — neural sentiment
    via [Bumblebee](https://hex.pm/packages/bumblebee) and a
    pre-trained multilingual transformer (XLM-RoBERTa). Higher quality
    but requires a model download and the optional `:bumblebee` dep.

  Routing is controlled by the `:backend` option to
  `Text.Sentiment.analyze/2` (and `label/2`), or globally via the
  `:sentiment_backend` application configuration:

      # config/config.exs
      config :text, :sentiment_backend, Text.Sentiment.Backends.Bumblebee

  Custom backends can be supplied by implementing this behaviour.

  """

  @typedoc "The structured result every backend returns."
  @type result :: %{
          required(:label) => :positive | :negative | :neutral,
          required(:compound) => float(),
          optional(:sum) => float(),
          optional(:tokens) => non_neg_integer(),
          optional(:matched) => non_neg_integer(),
          optional(:language) => atom() | nil,
          optional(:backend) => module()
        }

  @doc """
  Returns a sentiment result for `text`.

  Backends are free to interpret options however they see fit, but
  every backend must:

  * Accept any UTF-8 binary as input.

  * Always return a map with at least `:label` and `:compound`.

  * Either accept the standard `:language` option (atom, string, or
    `Localize.LanguageTag` — see `Text.Language.normalize/1`) or
    document loudly that they ignore it.

  """
  @callback analyze(String.t(), keyword()) :: result()

  @doc """
  Returns the backend module currently configured for use.

  The resolution order is:

  1. The `:backend` keyword option, if present.
  2. The application config value at `Application.get_env(:text, :sentiment_backend)`.
  3. The default — `Text.Sentiment.Backends.Lexicon`.

  ### Examples

      iex> Text.Sentiment.Backend.resolve([])
      Text.Sentiment.Backends.Lexicon

      iex> Text.Sentiment.Backend.resolve(backend: Text.Sentiment.Backends.Lexicon)
      Text.Sentiment.Backends.Lexicon

  """
  @spec resolve(keyword()) :: module()
  def resolve(options) when is_list(options) do
    case Keyword.fetch(options, :backend) do
      {:ok, mod} when is_atom(mod) ->
        mod

      :error ->
        Application.get_env(:text, :sentiment_backend, Text.Sentiment.Backends.Lexicon)
    end
  end
end
