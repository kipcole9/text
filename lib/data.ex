defmodule Text.Data do
  @moduledoc """
  Locates runtime data files used by Text modules, fetching them
  from upstream sources when permitted.

  Most modules in this package ship a small bundled dataset (e.g.
  `Text.Hyphenation` ships American English patterns, `Text.Lemma`
  ships English lemmatization data) but also accept additional
  language packs at runtime. This module is the single
  configuration surface those modules share for finding, caching,
  and optionally downloading those packs.

  ## Configuration

      config :text,
        # Where on-demand-downloaded data is cached.
        # Default: "~/.cache/text".
        data_dir: "~/.cache/text",

        # Per-domain auto-download permissions. All default to false:
        # the package never reaches out to the network without an
        # explicit opt-in for the relevant domain.
        auto_download_hyphenation_data: true,
        auto_download_lemma_data: true,
        auto_download_wordfreq_data: false

  ## Lookup order

  When a Text module asks for a data file via `fetch/3`:

  1. The configured `:data_dir` is checked first. Once a file has
     been cached there (whether downloaded by this package, copied
     manually, or shipped by a deployment script) it is reused on
     every subsequent call.

  2. The bundled `priv/<domain>/` directory inside the `:text`
     package is checked next.

  3. If a download URL is known and `auto_download_<domain>_data`
     is `true`, the file is downloaded to the cache directory and
     the cached path is returned.

  4. Otherwise `{:error, %ArgumentError{}}` is returned with a
     message describing how to resolve the situation (enable
     auto-download, or place the file manually).

  ## Domains

  Each Text module that needs runtime data uses its own domain
  atom — `:hyphenation`, `:lemma`, `:wordfreq`. Domains map
  directly to subdirectory names under both `priv/` and `:data_dir`,
  and to per-domain permission keys.

  """

  @default_data_dir "~/.cache/text"

  @doc """
  Returns the absolute path to the configured data directory.

  ### Returns

  * The expanded path. The directory is not created until the first
    download writes to it.

  ### Examples

      iex> is_binary(Text.Data.data_dir())
      true

  """
  @spec data_dir() :: String.t()
  def data_dir do
    (Application.get_env(:text, :data_dir) || @default_data_dir)
    |> Path.expand()
  end

  @doc """
  Returns `true` when auto-download is enabled for the named domain.

  ### Arguments

  * `domain` is an atom like `:hyphenation`. Looks up the
    application env key `:auto_download_<domain>_data`.

  ### Returns

  * A boolean. Defaults to `false` if the key is not set.

  """
  @spec auto_download?(atom()) :: boolean()
  def auto_download?(domain) when is_atom(domain) do
    Application.get_env(:text, :"auto_download_#{domain}_data", false)
  end

  @doc """
  Locates a data file for a domain, downloading it on demand when
  permitted.

  ### Arguments

  * `domain` is an atom naming the data category (e.g.
    `:hyphenation`). Used as the subdirectory name in both
    `:data_dir` and `priv/`, and as the prefix of the
    auto-download permission key.

  * `filename` is the name of the file to locate (e.g.
    `"hyph-de-1996.tex"`).

  ### Options

  * `:url` is the upstream URL to download from when the file is
    not already cached. Required for auto-download to work; without
    it, `fetch/3` only consults the cache and bundled directories.

  ### Returns

  * `{:ok, path}` — the file is available at `path`.

  * `{:error, %ArgumentError{}}` — the file could not be located
    and either no URL was provided or auto-download is disabled
    for the domain. The error message explains how to resolve.

  ### Examples

      iex> {:ok, path} = Text.Data.fetch(:hyphenation, "hyph-en-us.tex")
      iex> File.exists?(path)
      true

  """
  @spec fetch(atom(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def fetch(domain, filename, options \\ [])
      when is_atom(domain) and is_binary(filename) do
    url = Keyword.get(options, :url)

    cached_path = cache_path(domain, filename)
    bundled_path = bundled_path(domain, filename)

    cond do
      File.exists?(cached_path) ->
        {:ok, cached_path}

      File.exists?(bundled_path) ->
        {:ok, bundled_path}

      not is_nil(url) and auto_download?(domain) ->
        download(url, cached_path)

      true ->
        {:error, missing_data_error(domain, filename, url, cached_path, bundled_path)}
    end
  end

  @doc """
  Returns the cache path where a file would live (whether it does or not).

  Useful for tooling that wants to inspect or warm the cache.
  """
  @spec cache_path(atom(), String.t()) :: String.t()
  def cache_path(domain, filename) do
    Path.join([data_dir(), to_string(domain), filename])
  end

  @doc """
  Returns the bundled path where a file would live (whether it does or not).
  """
  @spec bundled_path(atom(), String.t()) :: String.t()
  def bundled_path(domain, filename) do
    Path.join([:code.priv_dir(:text), to_string(domain), filename])
  end

  defp download(url, dest_path) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    File.mkdir_p!(Path.dirname(dest_path))

    request = {String.to_charlist(url), []}

    http_options = [
      timeout: 600_000,
      connect_timeout: 30_000,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 4,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    options = [stream: String.to_charlist(dest_path), body_format: :binary]

    case :httpc.request(:get, request, http_options, options) do
      {:ok, :saved_to_file} ->
        {:ok, dest_path}

      {:ok, {{_, status, _}, _, _}} ->
        _ = File.rm(dest_path)
        {:error, %ArgumentError{message: "Download of #{url} failed: HTTP #{status}"}}

      {:error, reason} ->
        _ = File.rm(dest_path)
        {:error, %ArgumentError{message: "Download of #{url} failed: #{inspect(reason)}"}}
    end
  end

  defp missing_data_error(domain, filename, nil, cached_path, _bundled_path) do
    %ArgumentError{
      message:
        "Text.Data could not locate #{inspect(domain)} file #{inspect(filename)}. " <>
          "Place the file at #{cached_path} (or in the bundled priv/#{domain}/ directory)."
    }
  end

  defp missing_data_error(domain, filename, url, cached_path, _bundled_path) do
    config_key = "auto_download_#{domain}_data"

    %ArgumentError{
      message:
        "Text.Data could not locate #{inspect(domain)} file #{inspect(filename)}. " <>
          "Either set `config :text, #{config_key}: true` to allow on-demand download " <>
          "from #{url}, or place the file at #{cached_path}."
    }
  end
end
