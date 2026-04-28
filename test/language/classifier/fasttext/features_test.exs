defmodule Text.Language.Classifier.Fasttext.FeaturesTest do
  use ExUnit.Case, async: true

  alias Text.Language.Classifier.Fasttext.{
    Args,
    Dictionary,
    Entry,
    Features,
    Model
  }

  describe "extract/2 — synthetic model" do
    setup do
      args = %Args{
        dim: 4,
        ws: 0,
        epoch: 0,
        min_count: 0,
        neg: 0,
        word_ngrams: 1,
        loss: :softmax,
        model: :sup,
        bucket: 100,
        minn: 2,
        maxn: 4,
        lr_update_rate: 0,
        t: 0.0
      }

      entries = [
        %Entry{word: "hello", count: 5, type: :word},
        %Entry{word: "world", count: 4, type: :word},
        %Entry{word: "__label__en", count: 3, type: :label},
        %Entry{word: "__label__fr", count: 2, type: :label}
      ]

      dict = %Dictionary{
        size: 4,
        nwords: 2,
        nlabels: 2,
        ntokens: 14,
        pruneidx_size: -1,
        entries: entries,
        word_to_index: %{
          "hello" => 0,
          "world" => 1,
          "__label__en" => 2,
          "__label__fr" => 3
        },
        pruneidx: %{}
      }

      model = %Model{
        args: args,
        dictionary: dict,
        input_matrix: Nx.broadcast(0.0, {2 + 100, 4}),
        output_matrix: Nx.broadcast(0.0, {2, 4}),
        labels: ["en", "fr"]
      }

      {:ok, model: model}
    end

    test "in-vocab word emits its wid first, then subwords", %{model: model} do
      [head | _rest] = Features.extract("hello", model)
      assert head == 0
    end

    test "two in-vocab words concatenate", %{model: model} do
      hello = Features.extract("hello", model)
      world = Features.extract("world", model)
      assert Features.extract("hello world", model) == hello ++ world
    end

    test "OOV word emits subwords only (no leading wid)", %{model: model} do
      indices = Features.extract("qzx", model)
      Enum.each(indices, fn idx -> assert idx >= model.dictionary.nwords end)
    end

    test "known label entry is dropped", %{model: model} do
      assert Features.extract("__label__en", model) == []
    end

    test "OOV label-shaped token is dropped", %{model: model} do
      assert Features.extract("__label__zz", model) == []
    end

    test "label tokens do not leak into surrounding word features", %{model: model} do
      with_label = Features.extract("__label__en hello", model)
      without_label = Features.extract("hello", model)
      assert with_label == without_label
    end

    test "empty and whitespace-only input return []", %{model: model} do
      assert Features.extract("", model) == []
      assert Features.extract("   \t\n", model) == []
    end

    test "args.maxn <= 0 emits only the wid, no subwords", %{model: model} do
      model = put_in(model.args.maxn, 0)
      assert Features.extract("hello", model) == [0]
    end
  end

  describe "differential against fastText reference" do
    @fixture_path Path.expand("../../../fixtures/golden_features.json", __DIR__)
    @model_path Path.expand("../../../../priv/lid_176/lid.176.bin", __DIR__)

    setup do
      cond do
        not File.exists?(@model_path) ->
          {:skip, "skipping; download lid.176.bin via the download_model task"}

        not File.exists?(@fixture_path) ->
          {:skip, "skipping; generate via `python3 priv/scripts/generate_features_fixtures.py`"}

        true ->
          fixture = @fixture_path |> File.read!() |> :json.decode()

          {:ok, model} =
            Text.Language.Classifier.Fasttext.ModelLoader.load(@model_path)

          {:ok, fixture: fixture, model: model}
      end
    end

    @tag :requires_lid_176
    test "tokenization matches reference for every input", %{fixture: f} do
      mismatches =
        for entry <- f["entries"], reduce: [] do
          acc ->
            ours = Text.Language.Classifier.Fasttext.Tokenizer.tokenize(entry["text"])
            expected = entry["tokens"]

            if ours == expected do
              acc
            else
              [%{text: entry["text"], expected: expected, actual: ours} | acc]
            end
        end

      assert mismatches == []
    end

    @tag :requires_lid_176
    test "feature index sequence matches reference for every input", %{
      fixture: f,
      model: model
    } do
      mismatches =
        for entry <- f["entries"], reduce: [] do
          acc ->
            ours = Features.extract(entry["text"], model)
            expected = entry["features"]

            if ours == expected do
              acc
            else
              [
                %{
                  text: entry["text"],
                  expected_len: length(expected),
                  actual_len: length(ours),
                  first_diff_at: first_diff_index(expected, ours)
                }
                | acc
              ]
            end
        end

      assert mismatches == []
    end

    @tag :requires_lid_176
    test "per-token classification matches reference (word vs label vs OOV)", %{
      fixture: f,
      model: model
    } do
      mismatches =
        for entry <- f["entries"], reduce: [] do
          acc ->
            tokens = Text.Language.Classifier.Fasttext.Tokenizer.tokenize(entry["text"])

            mismatched_tokens =
              entry["per_token"]
              |> Enum.zip(tokens)
              |> Enum.flat_map(fn {ref, ours_token} ->
                ours_indices =
                  Features.extract(ours_token, model)

                expected_indices = ref["indices"]

                if ours_indices == expected_indices do
                  []
                else
                  [%{token: ours_token, expected: expected_indices, actual: ours_indices}]
                end
              end)

            acc ++ mismatched_tokens
        end

      assert mismatches == []
    end
  end

  defp first_diff_index([a | as], [a | bs]), do: 1 + first_diff_index(as, bs)
  defp first_diff_index(_, _), do: 0
end
