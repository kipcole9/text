defmodule Text.Language.Classifier.Fasttext.ModelLoaderTest do
  use ExUnit.Case, async: true

  alias Text.Language.Classifier.Fasttext.{Args, Dictionary, Entry, ModelLoader}
  alias Text.Test.FasttextFixture

  describe "decode_model/2 round-trips against the fixture encoder" do
    test "parses the minimal spec and returns the expected struct" do
      spec = FasttextFixture.minimal_spec()
      binary = FasttextFixture.build(spec)

      assert {:ok, model} = ModelLoader.decode_model(binary)

      assert %Args{
               dim: 4,
               bucket: 8,
               minn: 2,
               maxn: 4,
               loss: :softmax,
               model: :sup
             } = model.args

      assert %Dictionary{nwords: 1, nlabels: 2, size: 3, pruneidx_size: 0} = model.dictionary

      assert [
               %Entry{word: "hello", count: 5, type: :word},
               %Entry{word: "__label__en", count: 3, type: :label},
               %Entry{word: "__label__fr", count: 1, type: :label}
             ] = model.dictionary.entries

      assert %{"hello" => 0, "__label__en" => 1, "__label__fr" => 2} =
               model.dictionary.word_to_index

      assert model.labels == ["en", "fr"]

      assert Nx.shape(model.input_matrix) == {9, 4}
      assert Nx.type(model.input_matrix) == {:f, 32}
      assert Nx.shape(model.output_matrix) == {2, 4}
    end

    test "preserves matrix values bit-for-bit" do
      input_matrix = [
        [1.0, 2.0, 3.0, 4.0],
        [5.0, 6.0, 7.0, 8.0],
        [-1.0, -2.0, -3.0, -4.0]
      ]

      output_matrix = [
        [0.5, 0.25, 0.125, 0.0625],
        [-0.5, -0.25, -0.125, -0.0625]
      ]

      spec =
        FasttextFixture.minimal_spec()
        |> Map.merge(%{
          args: %{dim: 4, bucket: 2, minn: 2, maxn: 4},
          input_matrix: input_matrix,
          output_matrix: output_matrix
        })

      assert {:ok, model} = ModelLoader.decode_model(FasttextFixture.build(spec))

      assert Nx.to_list(model.input_matrix) == input_matrix
      assert Nx.to_list(model.output_matrix) == output_matrix
    end

    test "reads pruneidx pairs without affecting subsequent sections" do
      spec =
        FasttextFixture.minimal_spec()
        |> Map.put(:pruneidx, [{1, 2}, {3, 4}, {5, 6}])

      assert {:ok, model} = ModelLoader.decode_model(FasttextFixture.build(spec))

      assert model.dictionary.pruneidx_size == 3
      assert model.dictionary.pruneidx == %{1 => 2, 3 => 4, 5 => 6}
      assert model.labels == ["en", "fr"]
    end

    test "round-trips a UTF-8 multibyte word" do
      spec =
        FasttextFixture.minimal_spec()
        |> Map.put(:entries, [
          {"héllo", 5, :word},
          {"日本語", 2, :word},
          {"__label__en", 3, :label},
          {"__label__zh-Hans", 1, :label}
        ])
        |> Map.put(:input_matrix, FasttextFixture.zero_matrix(2 + 8, 4))
        |> Map.put(:output_matrix, FasttextFixture.zero_matrix(2, 4))

      assert {:ok, model} = ModelLoader.decode_model(FasttextFixture.build(spec))

      words = Enum.map(model.dictionary.entries, & &1.word)
      assert words == ["héllo", "日本語", "__label__en", "__label__zh-Hans"]
      assert model.labels == ["en", "zh-Hans"]
    end
  end

  describe "decode_model/2 error handling" do
    test "rejects bad magic" do
      spec = FasttextFixture.minimal_spec()
      binary = FasttextFixture.build(Map.put(spec, :magic, 1))

      assert {:error, {:bad_magic, 1}} = ModelLoader.decode_model(binary)
    end

    test "rejects future versions" do
      spec = FasttextFixture.minimal_spec()
      binary = FasttextFixture.build(Map.put(spec, :version, 99))

      assert {:error, {:unsupported_version, 99}} = ModelLoader.decode_model(binary)
    end

    test "rejects quantized input" do
      spec = FasttextFixture.minimal_spec()
      binary = FasttextFixture.build(Map.put(spec, :quant_input, true))

      assert {:error, {:quantized_input_unsupported, true}} =
               ModelLoader.decode_model(binary)
    end

    test "rejects quantized output" do
      spec = FasttextFixture.minimal_spec()
      binary = FasttextFixture.build(Map.put(spec, :quant_output, true))

      assert {:error, {:quantized_output_unsupported, true}} =
               ModelLoader.decode_model(binary)
    end

    test "rejects truncated header" do
      assert {:error, :truncated_header} = ModelLoader.decode_model(<<1, 2, 3>>)
    end

    test "rejects mismatched input matrix shape" do
      # Build a spec where the input matrix has the wrong number of rows
      # (5 instead of nwords + bucket = 9). The fixture encoder writes the
      # row count straight from the supplied matrix, so the parser sees
      # m=5 but expects m=9.
      spec =
        FasttextFixture.minimal_spec()
        |> Map.put(:input_matrix, FasttextFixture.zero_matrix(5, 4))

      binary = FasttextFixture.build(spec)

      assert {:error, {:input_matrix_shape_mismatch, %{expected: {9, 4}, actual: {5, 4}}}} =
               ModelLoader.decode_model(binary)
    end

    test "rejects mismatched output matrix shape" do
      spec =
        FasttextFixture.minimal_spec()
        |> Map.put(:output_matrix, FasttextFixture.zero_matrix(5, 4))

      binary = FasttextFixture.build(spec)

      assert {:error, {:output_matrix_shape_mismatch, %{expected: {2, 4}, actual: {5, 4}}}} =
               ModelLoader.decode_model(binary)
    end
  end

  describe "load/2" do
    @tag :tmp_dir
    test "loads a model from disk", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "tiny_model.bin")
      binary = FasttextFixture.build(FasttextFixture.minimal_spec())
      File.write!(path, binary)

      assert {:ok, model} = ModelLoader.load(path)
      assert model.dictionary.nlabels == 2
    end

    test "returns posix error for missing file" do
      assert {:error, :enoent} = ModelLoader.load("/nonexistent/path/to/model.bin")
    end
  end

  describe "lid.176.bin (when present)" do
    @lid_path Path.expand("../../../../priv/lid_176/lid.176.bin", __DIR__)

    @describetag :requires_lid_176

    setup do
      if File.exists?(@lid_path) do
        :ok
      else
        {:skip, "skipping; download lid.176.bin via mix text.download_model"}
      end
    end

    test "parses the official lid.176 model" do
      assert {:ok, model} = ModelLoader.load(@lid_path)

      # Documented lid.176 hyperparameters.
      assert model.args.dim == 16
      assert model.args.minn == 2
      assert model.args.maxn == 4
      assert model.args.loss == :hs
      assert model.args.model == :sup
      assert model.args.bucket == 2_000_000

      assert model.dictionary.nlabels == 176
      assert length(model.labels) == 176
      assert "en" in model.labels
      assert "fr" in model.labels

      assert Nx.shape(model.input_matrix) ==
               {model.dictionary.nwords + model.args.bucket, 16}

      assert Nx.shape(model.output_matrix) == {176, 16}
    end
  end
end
