defmodule Text.Test.FasttextFixture do
  @moduledoc false

  # Helpers for assembling synthetic fastText `.bin` model binaries in
  # tests. The encoders here are the inverse of
  # `Text.Language.Classifier.Fasttext.ModelLoader` — together they form a
  # round-trip property the parser tests depend on.
  #
  # Mirrors the byte layout documented in `docs/lid176_binary_format.md`.

  @magic 793_712_314
  @current_version 12

  @doc """
  Builds a fully-formed fastText `.bin` binary from a high-level spec.

  The spec is a map with the following required keys:

  * `:args` — a map of args fields (`:dim`, `:bucket`, `:minn`, `:maxn`,
    plus other training fields). Defaults are filled in for missing
    training-only fields.

  * `:entries` — a list of `{word, count, type}` tuples in file order.
    `type` is either `:word` or `:label`.

  * `:input_matrix` — list of lists of floats, shape `{nwords + bucket, dim}`.

  * `:output_matrix` — list of lists of floats, shape `{nlabels, dim}`.

  Optional keys:

  * `:version` — defaults to 12.
  * `:magic` — defaults to the canonical fastText magic.
  * `:quant_input` — boolean, defaults to false.
  * `:quant_output` — boolean, defaults to false.
  * `:pruneidx` — list of `{int, int}` pairs, defaults to `[]`.
  """
  def build(spec) do
    magic = Map.get(spec, :magic, @magic)
    version = Map.get(spec, :version, @current_version)
    args = Map.fetch!(spec, :args)
    entries = Map.fetch!(spec, :entries)
    pruneidx = Map.get(spec, :pruneidx, [])
    quant_input = Map.get(spec, :quant_input, false)
    quant_output = Map.get(spec, :quant_output, false)
    input_matrix = Map.fetch!(spec, :input_matrix)
    output_matrix = Map.fetch!(spec, :output_matrix)

    nwords = Enum.count(entries, &(elem(&1, 2) == :word))
    nlabels = Enum.count(entries, &(elem(&1, 2) == :label))

    [
      <<magic::little-signed-32, version::little-signed-32>>,
      encode_args(args),
      encode_dictionary(entries, nwords, nlabels, pruneidx),
      <<bool_byte(quant_input)>>,
      encode_dense_matrix(input_matrix),
      <<bool_byte(quant_output)>>,
      encode_dense_matrix(output_matrix)
    ]
    |> IO.iodata_to_binary()
  end

  @doc """
  Returns a small, valid spec suitable as a base for tests.

  Two language labels (`en`, `fr`), one word, `dim = 4`, `bucket = 8` so
  the input matrix is `{1 + 8, 4}` = 9 rows of 4 floats.
  """
  def minimal_spec do
    dim = 4
    bucket = 8
    nwords = 1
    nlabels = 2

    %{
      args: %{dim: dim, bucket: bucket, minn: 2, maxn: 4},
      entries: [
        {"hello", 5, :word},
        {"__label__en", 3, :label},
        {"__label__fr", 1, :label}
      ],
      input_matrix: zero_matrix(nwords + bucket, dim),
      output_matrix: zero_matrix(nlabels, dim)
    }
  end

  def zero_matrix(rows, cols) do
    row = List.duplicate(0.0, cols)
    List.duplicate(row, rows)
  end

  # ---- internal encoders ---------------------------------------------------

  defp encode_args(args) do
    %{
      dim: dim,
      bucket: bucket,
      minn: minn,
      maxn: maxn
    } = Map.merge(default_args(), args)

    ws = Map.get(args, :ws, 5)
    epoch = Map.get(args, :epoch, 1)
    min_count = Map.get(args, :min_count, 1)
    neg = Map.get(args, :neg, 5)
    word_ngrams = Map.get(args, :word_ngrams, 1)
    loss = encode_loss(Map.get(args, :loss, :softmax))
    model = encode_model(Map.get(args, :model, :sup))
    lr_update_rate = Map.get(args, :lr_update_rate, 100)
    t = Map.get(args, :t, 1.0e-4)

    <<
      dim::little-signed-32,
      ws::little-signed-32,
      epoch::little-signed-32,
      min_count::little-signed-32,
      neg::little-signed-32,
      word_ngrams::little-signed-32,
      loss::little-signed-32,
      model::little-signed-32,
      bucket::little-signed-32,
      minn::little-signed-32,
      maxn::little-signed-32,
      lr_update_rate::little-signed-32,
      t::little-float-64
    >>
  end

  defp default_args do
    %{dim: 16, bucket: 2_000_000, minn: 2, maxn: 4}
  end

  defp encode_loss(:hs), do: 1
  defp encode_loss(:ns), do: 2
  defp encode_loss(:softmax), do: 3
  defp encode_loss(:ova), do: 4

  defp encode_model(:cbow), do: 1
  defp encode_model(:sg), do: 2
  defp encode_model(:sup), do: 3

  defp encode_dictionary(entries, nwords, nlabels, pruneidx) do
    size = length(entries)
    ntokens = Enum.reduce(entries, 0, fn {_w, c, _t}, acc -> acc + c end)
    pruneidx_size = length(pruneidx)

    header =
      <<
        size::little-signed-32,
        nwords::little-signed-32,
        nlabels::little-signed-32,
        ntokens::little-signed-64,
        pruneidx_size::little-signed-64
      >>

    entry_bytes =
      for {word, count, type} <- entries, into: <<>> do
        type_byte =
          case type do
            :word -> 0
            :label -> 1
          end

        word <> <<0, count::little-signed-64, type_byte::little-signed-8>>
      end

    pruneidx_bytes =
      for {first, second} <- pruneidx, into: <<>> do
        <<first::little-signed-32, second::little-signed-32>>
      end

    header <> entry_bytes <> pruneidx_bytes
  end

  defp encode_dense_matrix([]) do
    <<0::little-signed-64, 0::little-signed-64>>
  end

  defp encode_dense_matrix(rows) do
    m = length(rows)
    n = rows |> hd() |> length()

    data =
      for row <- rows, value <- row, into: <<>> do
        <<value::little-float-32>>
      end

    <<m::little-signed-64, n::little-signed-64>> <> data
  end

  defp bool_byte(false), do: 0
  defp bool_byte(true), do: 1
end
