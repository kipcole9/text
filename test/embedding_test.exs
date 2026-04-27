defmodule Text.EmbeddingTest do
  use ExUnit.Case, async: true

  alias Text.Embedding

  @tmp_path System.tmp_dir!() |> Path.join("text_embedding_test")

  setup do
    File.mkdir_p!(@tmp_path)

    on_exit(fn ->
      File.rm_rf!(@tmp_path)
    end)

    :ok
  end

  defp write_vec(filename, content) do
    path = Path.join(@tmp_path, filename)
    File.write!(path, content)
    path
  end

  describe "load/2" do
    test "parses fastText .vec format" do
      path =
        write_vec("simple.vec", """
        3 2
        cat 0.5 0.5
        dog 0.4 0.6
        carrot -0.8 0.1
        """)

      assert {:ok, emb} = Embedding.load(path)
      assert emb.n == 3
      assert emb.dim == 2
      assert emb.vocab == %{"cat" => 0, "dog" => 1, "carrot" => 2}
      assert Nx.shape(emb.vectors) == {3, 2}
      assert Nx.type(emb.vectors) == {:f, 32}
    end

    test "handles tokens with multibyte UTF-8" do
      path =
        write_vec("utf8.vec", """
        2 2
        café 0.5 0.5
        naïve 0.4 0.6
        """)

      assert {:ok, emb} = Embedding.load(path)
      assert Map.has_key?(emb.vocab, "café")
      assert Map.has_key?(emb.vocab, "naïve")
    end

    test "rejects malformed header" do
      path = write_vec("bad.vec", "not a header line\nfoo 1 2 3\n")

      assert {:error, :malformed_header} = Embedding.load(path)
    end

    test "skips lines whose vector size doesn't match dim" do
      path =
        write_vec("ragged.vec", """
        3 2
        good 0.1 0.2
        wrong 0.5 0.5 0.5
        ok 0.3 0.4
        """)

      assert {:ok, emb} = Embedding.load(path)
      # Two valid lines: good, ok.
      assert emb.n == 2
      assert Map.has_key?(emb.vocab, "good")
      assert Map.has_key?(emb.vocab, "ok")
      refute Map.has_key?(emb.vocab, "wrong")
    end

    test ":filter restricts which tokens are loaded" do
      path =
        write_vec("filter.vec", """
        4 2
        cat 0.5 0.5
        dog 0.4 0.6
        fox 0.3 0.7
        bird 0.2 0.8
        """)

      assert {:ok, emb} = Embedding.load(path, filter: ["cat", "fox"])

      assert emb.n == 2
      assert Map.keys(emb.vocab) |> Enum.sort() == ["cat", "fox"]
    end

    test ":max_tokens caps the load" do
      path =
        write_vec("cap.vec", """
        4 2
        cat 0.5 0.5
        dog 0.4 0.6
        fox 0.3 0.7
        bird 0.2 0.8
        """)

      assert {:ok, emb} = Embedding.load(path, max_tokens: 2)
      assert emb.n == 2
    end

    test "missing file returns posix error" do
      assert {:error, :enoent} = Embedding.load("/no/such/file.vec")
    end
  end

  describe "vector/2" do
    setup do
      path =
        write_vec("v.vec", """
        2 3
        cat 0.5 0.5 0.5
        dog 0.6 0.5 0.4
        """)

      {:ok, emb} = Embedding.load(path)
      {:ok, emb: emb}
    end

    test "returns the vector for an in-vocab token", %{emb: emb} do
      v = Embedding.vector(emb, "cat")
      assert Nx.shape(v) == {3}
      assert Nx.to_list(v) == [0.5, 0.5, 0.5]
    end

    test "returns nil for missing tokens", %{emb: emb} do
      assert Embedding.vector(emb, "missing") == nil
    end
  end

  describe "similarity/3" do
    setup do
      path =
        write_vec("s.vec", """
        4 3
        a 1.0 0.0 0.0
        b 1.0 0.0 0.0
        c 0.0 1.0 0.0
        d -1.0 0.0 0.0
        """)

      {:ok, emb} = Embedding.load(path)
      {:ok, emb: emb}
    end

    test "identical vectors give similarity 1.0", %{emb: emb} do
      assert_in_delta Embedding.similarity(emb, "a", "b"), 1.0, 1.0e-5
    end

    test "orthogonal vectors give similarity 0.0", %{emb: emb} do
      assert_in_delta Embedding.similarity(emb, "a", "c"), 0.0, 1.0e-5
    end

    test "opposite vectors give similarity -1.0", %{emb: emb} do
      assert_in_delta Embedding.similarity(emb, "a", "d"), -1.0, 1.0e-5
    end

    test "missing tokens give nil", %{emb: emb} do
      assert Embedding.similarity(emb, "a", "missing") == nil
      assert Embedding.similarity(emb, "missing", "a") == nil
    end
  end

  describe "nearest/3" do
    setup do
      path =
        write_vec("n.vec", """
        5 3
        king 0.5 0.5 0.5
        queen 0.6 0.5 0.4
        prince 0.55 0.45 0.45
        carrot -0.8 0.1 0.0
        rock -0.5 -0.5 -0.5
        """)

      {:ok, emb} = Embedding.load(path)
      {:ok, emb: emb}
    end

    test "returns nearest neighbours by cosine similarity", %{emb: emb} do
      [{first, _} | _] = Embedding.nearest(emb, "king", k: 3)
      assert first in ["queen", "prince"]
    end

    test "excludes the query token from results", %{emb: emb} do
      results = Embedding.nearest(emb, "king", k: 5)
      tokens = Enum.map(results, fn {t, _} -> t end)
      refute "king" in tokens
    end

    test "results are sorted descending", %{emb: emb} do
      results = Embedding.nearest(emb, "king", k: 4)
      sims = Enum.map(results, fn {_t, s} -> s end)
      assert sims == Enum.sort(sims, :desc)
    end

    test "missing token returns []", %{emb: emb} do
      assert Embedding.nearest(emb, "missing") == []
    end
  end

  describe "analogy/5" do
    setup do
      # Construct a synthetic embedding where king-man+woman ≈ queen.
      path =
        write_vec("a.vec", """
        4 4
        king 1.0 0.0 0.5 0.0
        man 0.0 0.0 0.5 0.0
        woman 0.0 1.0 0.5 0.0
        queen 1.0 1.0 0.5 0.0
        """)

      {:ok, emb} = Embedding.load(path)
      {:ok, emb: emb}
    end

    test "king : man :: woman : ? finds queen", %{emb: emb} do
      assert [{"queen", _} | _] = Embedding.analogy(emb, "king", "man", "woman", k: 1)
    end

    test "the three input tokens are excluded from the result", %{emb: emb} do
      results = Embedding.analogy(emb, "king", "man", "woman", k: 4)
      tokens = Enum.map(results, fn {t, _} -> t end)
      refute "king" in tokens
      refute "man" in tokens
      refute "woman" in tokens
    end

    test "returns [] when any input token is missing", %{emb: emb} do
      assert Embedding.analogy(emb, "king", "man", "missing") == []
      assert Embedding.analogy(emb, "missing", "man", "woman") == []
    end
  end

  describe "size/1" do
    test "returns the loaded vocab size" do
      path =
        write_vec("size.vec", """
        3 2
        a 1.0 0.0
        b 0.0 1.0
        c 0.5 0.5
        """)

      {:ok, emb} = Embedding.load(path)
      assert Embedding.size(emb) == 3
    end
  end
end
