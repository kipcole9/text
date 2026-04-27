defmodule Text.Language.Classifier.Fasttext.InferenceTest do
  use ExUnit.Case, async: true

  alias Text.Language.Classifier.Fasttext.{
    Args,
    Dictionary,
    Entry,
    HuffmanTree,
    Inference,
    Model
  }

  describe "compute_hidden/2" do
    test "averages selected rows" do
      input_matrix =
        Nx.tensor(
          [
            [1.0, 2.0, 3.0, 4.0],
            [5.0, 6.0, 7.0, 8.0],
            [9.0, 10.0, 11.0, 12.0]
          ],
          type: {:f, 32}
        )

      hidden = Inference.compute_hidden([0, 2], input_matrix)

      # mean of rows 0 and 2: [(1+9)/2, (2+10)/2, (3+11)/2, (4+12)/2]
      assert Nx.to_list(hidden) == [5.0, 6.0, 7.0, 8.0]
    end

    test "empty feature list returns a zero vector matching dim" do
      input_matrix = Nx.tensor([[1.0, 2.0, 3.0]], type: {:f, 32})
      hidden = Inference.compute_hidden([], input_matrix)

      assert Nx.shape(hidden) == {3}
      assert Nx.to_list(hidden) == [0.0, 0.0, 0.0]
    end
  end

  describe "predict_features/3 with synthetic softmax model" do
    setup do
      # Tiny softmax model: dim=2, two labels, two words.
      args = %Args{
        dim: 2,
        ws: 0,
        epoch: 0,
        min_count: 0,
        neg: 0,
        word_ngrams: 1,
        loss: :softmax,
        model: :sup,
        bucket: 0,
        minn: 0,
        maxn: 0,
        lr_update_rate: 0,
        t: 0.0
      }

      dict = %Dictionary{
        size: 4,
        nwords: 2,
        nlabels: 2,
        ntokens: 2,
        pruneidx_size: -1,
        entries: [
          %Entry{word: "cat", count: 1, type: :word},
          %Entry{word: "dog", count: 1, type: :word},
          %Entry{word: "__label__animal", count: 1, type: :label},
          %Entry{word: "__label__plant", count: 1, type: :label}
        ],
        word_to_index: %{"cat" => 0, "dog" => 1, "__label__animal" => 2, "__label__plant" => 3},
        pruneidx: %{}
      }

      input_matrix = Nx.tensor([[1.0, 0.0], [0.0, 1.0]], type: {:f, 32})
      output_matrix = Nx.tensor([[2.0, 0.0], [0.0, 2.0]], type: {:f, 32})

      model = %Model{
        args: args,
        dictionary: dict,
        input_matrix: input_matrix,
        output_matrix: output_matrix,
        labels: ["animal", "plant"],
        loss_state: nil
      }

      {:ok, model: model}
    end

    test "single feature row picks its label", %{model: model} do
      [{label, prob}] = Inference.predict_features([0], model, k: 1)

      assert label == "animal"
      # softmax([2*1+0*0, 0*1+2*0]) = softmax([2, 0]) ≈ [0.881, 0.119]
      assert_in_delta prob, 0.881, 0.01
    end

    test "k=2 returns both labels in descending probability order", %{model: model} do
      [{l1, p1}, {l2, p2}] = Inference.predict_features([1], model, k: 2)
      assert l1 == "plant"
      assert l2 == "animal"
      assert p1 > p2
      assert_in_delta p1 + p2, 1.0, 1.0e-6
    end

    test "threshold drops low-probability candidates", %{model: model} do
      preds = Inference.predict_features([0], model, k: 2, threshold: 0.5)

      assert length(preds) == 1
      assert {"animal", _} = hd(preds)
    end

    test "empty feature list returns []", %{model: model} do
      assert Inference.predict_features([], model, k: 5) == []
    end
  end

  describe "predict_features/3 with synthetic hs model" do
    setup do
      # Three labels, dim=2. Build a Huffman tree so paths are
      # deterministic.
      args = %Args{
        dim: 2,
        ws: 0,
        epoch: 0,
        min_count: 0,
        neg: 0,
        word_ngrams: 1,
        loss: :hs,
        model: :sup,
        bucket: 0,
        minn: 0,
        maxn: 0,
        lr_update_rate: 0,
        t: 0.0
      }

      counts = [10, 5, 1]
      tree = HuffmanTree.build(counts)

      # Three labels → tree has 5 nodes: 0..2 leaves, 3 and 4 internal.
      # Output rows correspond to internal nodes 3-osz=0 and 4-osz=1.
      # Row 0 weights internal node 3; row 1 weights root (node 4).
      output_matrix = Nx.tensor([[1.0, 0.0], [0.0, 1.0]], type: {:f, 32})

      model = %Model{
        args: args,
        dictionary: %Dictionary{
          size: 3,
          nwords: 0,
          nlabels: 3,
          ntokens: 16,
          pruneidx_size: -1,
          entries: [
            %Entry{word: "__label__a", count: 10, type: :label},
            %Entry{word: "__label__b", count: 5, type: :label},
            %Entry{word: "__label__c", count: 1, type: :label}
          ],
          word_to_index: %{},
          pruneidx: %{}
        },
        input_matrix: Nx.tensor([[1.0, 1.0]], type: {:f, 32}),
        output_matrix: output_matrix,
        labels: ["a", "b", "c"],
        loss_state: tree
      }

      {:ok, model: model, tree: tree}
    end

    test "DFS produces probabilities that sum to ~1", %{model: model} do
      preds = Inference.predict_features([0], model, k: 3)
      total = Enum.reduce(preds, 0.0, fn {_, p}, acc -> acc + p end)
      assert_in_delta total, 1.0, 1.0e-3
    end

    test "k=1 returns the single most probable label", %{model: model} do
      [{label, _}] = Inference.predict_features([0], model, k: 1)
      assert label in ["a", "b", "c"]
    end
  end

  describe "differential against fastText reference" do
    @predict_fixture Path.expand("../../../fixtures/golden_predictions.json", __DIR__)
    @model_path Path.expand("../../../../priv/lid_176/lid.176.bin", __DIR__)

    setup do
      cond do
        not File.exists?(@model_path) ->
          {:skip, "skipping; download lid.176.bin"}

        not File.exists?(@predict_fixture) ->
          {:skip, "skipping; generate via priv/scripts/generate_predict_fixtures.py"}

        true ->
          fixture = @predict_fixture |> File.read!() |> :json.decode()

          {:ok, model} =
            Text.Language.Classifier.Fasttext.ModelLoader.load(@model_path)

          {:ok, fixture: fixture, model: model}
      end
    end

    @tag :requires_lid_176
    test "top-1 label matches the reference for every input", %{
      fixture: f,
      model: model
    } do
      mismatches =
        for entry <- f["entries"], reduce: [] do
          acc ->
            expected_top = entry["predictions"] |> hd() |> Map.fetch!("label")
            [{ours_top, _}] = Inference.predict(entry["text"], model, k: 1)

            if ours_top == expected_top do
              acc
            else
              [%{text: entry["text"], expected: expected_top, actual: ours_top} | acc]
            end
        end

      assert mismatches == []
    end

    @tag :requires_lid_176
    test "ordered label prefix matches the reference (above-noise predictions)", %{
      fixture: f,
      model: model
    } do
      # The reference's bottom predictions are routinely sub-1e-5 — at
      # the noise floor of fastText's `std_log(threshold + 1e-5)` cutoff
      # and squarely inside the f32-vs-f64 rounding band. Require
      # ordered-label parity only for the prefix where the reference's
      # probability is clearly above that floor (1e-3). Below that, both
      # implementations are equally "right" within rounding.
      k = f["top_k"]
      noise_floor = 1.0e-3

      mismatches =
        for entry <- f["entries"], reduce: [] do
          acc ->
            expected =
              entry["predictions"]
              |> Enum.take_while(fn p -> Map.fetch!(p, "probability") >= noise_floor end)
              |> Enum.map(&Map.fetch!(&1, "label"))

            ours_labels =
              entry["text"]
              |> Inference.predict(model, k: k)
              |> Enum.map(fn {l, _} -> l end)

            if expected == Enum.take(ours_labels, length(expected)) do
              acc
            else
              [%{text: entry["text"], expected: expected, actual: ours_labels} | acc]
            end
        end

      assert mismatches == []
    end

    @tag :requires_lid_176
    test "top-1 probability agrees with reference within 1e-3", %{
      fixture: f,
      model: model
    } do
      mismatches =
        for entry <- f["entries"], reduce: [] do
          acc ->
            expected_prob =
              entry["predictions"] |> hd() |> Map.fetch!("probability")

            [{_, ours_prob}] = Inference.predict(entry["text"], model, k: 1)
            delta = abs(ours_prob - expected_prob)

            if delta < 1.0e-3 do
              acc
            else
              [%{text: entry["text"], expected: expected_prob, actual: ours_prob, delta: delta} | acc]
            end
        end

      assert mismatches == []
    end
  end
end
