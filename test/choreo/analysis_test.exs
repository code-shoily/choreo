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

  defmodule UnsupportedStruct do
    defstruct [:foo]
  end

  describe "path/4 and highlight/1" do
    test "finds paths by different measures" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.add_service(:c)
        |> Choreo.connect(:a, :b, cost: 5)
        |> Choreo.connect(:b, :c, cost: 2)
        |> Choreo.connect(:a, :c, cost: 20)

      system =
        system
        |> put_in([Access.key(:graph), Access.key(:nodes), :b, :latency_ms], 50)
        |> put_in([Access.key(:graph), Access.key(:nodes), :b, :risk_score], 2)
        |> put_in([Access.key(:graph), Access.key(:nodes), :b, :rate], 100)
        |> put_in([Access.key(:graph), Access.key(:nodes), :c, :latency_ms], 10)
        |> put_in([Access.key(:graph), Access.key(:nodes), :c, :risk_score], 1)
        |> put_in([Access.key(:graph), Access.key(:nodes), :c, :rate], 500)

      assert {:ok, path_lat} = Analysis.path(system, :a, :c, measure: :latency)
      assert path_lat.nodes == [:a, :c]

      assert {:ok, path_tp} = Analysis.path(system, :a, :c, measure: :throughput)
      assert path_tp.nodes in [[:a, :c], [:a, :b, :c]]

      assert {:ok, path_risk} = Analysis.path(system, :a, :c, measure: :risk)
      assert path_risk.nodes == [:a, :c]

      assert {:ok, path_custom} = Analysis.path(system, :a, :c, measure: :cost)
      assert path_custom.nodes in [[:a, :c], [:a, :b, :c]]

      assert {:ok, path_fn} =
               Analysis.path(system, :a, :c, weight_fn: fn _d, _s, _t, _eid -> 1 end)

      assert path_fn.nodes in [[:a, :c], [:a, :b, :c]]

      assert {:ok, path_widest} =
               Analysis.path(system, :a, :c, measure: :weighted, algorithm: :widest)

      assert length(path_widest.nodes) >= 2

      # highlight/1
      assert Analysis.highlight(path_lat) == [
               highlighted_nodes: [:a, :c],
               highlighted_edges: [{:a, :c}]
             ]

      assert Analysis.highlight(nil) == []
    end

    test "reduce_transitive/1 simplifies multi-hop shortcuts" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.add_service(:c)
        |> Choreo.connect(:a, :b)
        |> Choreo.connect(:b, :c)
        |> Choreo.connect(:a, :c)

      assert {:ok, reduced} = Analysis.reduce_transitive(system)
      assert length(Choreo.edges(reduced)) == 2
    end

    test "raises on unsupported diagram type" do
      assert_raise ArgumentError, ~r/is not analysis-ready/, fn ->
        Analysis.path(%UnsupportedStruct{}, :a, :b)
      end
    end
  end
end
