defmodule Choreo.AnalysisTest do
  use ExUnit.Case
  alias Choreo.Analysis

  describe "mst/2" do
    test "kruskal algorithm (default)" do
      system =
        Choreo.new(directed: false)
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b, cost: 10)

      assert {:ok, result} = Analysis.mst(system, algorithm: :kruskal)
      assert result.total_weight == 10
    end

    test "prim algorithm" do
      system =
        Choreo.new(directed: false)
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b, cost: 10)

      assert {:ok, result} = Analysis.mst(system, algorithm: :prim)
      assert result.total_weight == 10
    end

    test "boruvka algorithm" do
      system =
        Choreo.new(directed: false)
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b, cost: 10)

      assert {:ok, result} = Analysis.mst(system, algorithm: :boruvka)
      assert result.total_weight == 10
    end

    test "returns error for unknown algorithm" do
      system = Choreo.new()
      assert {:error, "Unknown algorithm: magic"} = Analysis.mst(system, algorithm: :magic)
    end
  end

  describe "centrality/2" do
    test "degree centrality (modes)" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b)

      res_total = Analysis.centrality(system, mode: :total_degree)
      assert {:a, 1.0} in res_total
      assert {:b, 1.0} in res_total

      res_out = Analysis.centrality(system, mode: :out_degree)
      assert {:a, 1.0} in res_out
      assert {:b, 0.0} in res_out

      res_in = Analysis.centrality(system, mode: :in_degree)
      assert {:a, 0.0} in res_in
      assert {:b, 1.0} in res_in
    end

    test "betweenness centrality" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.add_service(:c)
        |> Choreo.connect(:a, :b)
        |> Choreo.connect(:b, :c)

      # b is between a and c
      results = Analysis.centrality(system, measure: :betweenness)
      assert {:b, score} = Enum.find(results, fn {id, _} -> id == :b end)
      assert score > 0
    end

    test "closeness centrality" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.add_service(:c)
        |> Choreo.connect(:a, :b)
        |> Choreo.connect(:b, :c)

      results = Analysis.centrality(system, measure: :closeness)
      assert length(results) == 3
    end

    test "pagerank centrality" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b)
        |> Choreo.connect(:b, :a)

      results = Analysis.centrality(system, measure: :pagerank)
      assert length(results) == 2
    end
  end

  describe "validate/1" do
    test "detects cycles" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b)
        |> Choreo.connect(:b, :a)

      issues = Analysis.validate(system)
      assert Enum.any?(issues, fn {sev, msg} -> sev == :error and msg =~ "Cycle detected" end)
    end

    test "detects isolated nodes" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)

      issues = Analysis.validate(system)
      assert Enum.any?(issues, fn {sev, msg} -> sev == :warning and msg =~ "Isolated nodes" end)
    end

    test "detects bridges and spofs" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.add_service(:c)
        |> Choreo.connect(:a, :b)
        |> Choreo.connect(:b, :c)

      issues = Analysis.validate(system)

      assert Enum.any?(issues, fn {sev, msg} ->
               sev == :warning and msg =~ "Single points of failure"
             end)

      assert Enum.any?(issues, fn {sev, msg} -> sev == :warning and msg =~ "Bridge edges" end)
    end
  end
end
