defmodule Choreo.InternalTest do
  use ExUnit.Case
  alias Choreo.Internal
  alias Choreo.Theme

  describe "bfs_reachable/2" do
    test "works with multiple seeds" do
      graph =
        Yog.new(:directed)
        |> Yog.add_node(:a, %{})
        |> Yog.add_node(:b, %{})
        |> Yog.add_node(:c, %{})
        |> Yog.add_edge_ensure(:a, :b, 1)

      reached = Internal.bfs_reachable(graph, [:a, :c])
      assert MapSet.member?(reached, :a)
      assert MapSet.member?(reached, :b)
      assert MapSet.member?(reached, :c)
    end
  end

  describe "build_cluster_subgraphs/2" do
    test "returns empty list when no clusters" do
      struct = %{clusters: %{}, graph: %{nodes: %{}}}
      assert Internal.build_cluster_subgraphs(struct, Theme.default()) == []
    end

    test "handles nested clusters" do
      struct = %{
        clusters: %{
          "cluster_parent" => %{label: "Parent"},
          "cluster_child" => %{label: "Child", parent: "parent"}
        },
        graph: %{
          nodes: %{
            a: %{cluster: "cluster_parent"},
            b: %{cluster: "cluster_child"}
          }
        }
      }

      subgraphs = Internal.build_cluster_subgraphs(struct, Theme.default())
      assert length(subgraphs) == 1
      parent = hd(subgraphs)
      assert parent.name == "cluster_parent"
      assert length(parent.subgraphs) == 1
      assert hd(parent.subgraphs).name == "cluster_child"
    end
  end

  describe "best_predecessor/3" do
    test "returns nil when no predecessors" do
      graph = Yog.new(:directed) |> Yog.add_node(:a, %{})
      assert Internal.best_predecessor(graph, :a, %{}) == nil
    end

    test "skips predecessors not in acc" do
      graph =
        Yog.new(:directed)
        |> Yog.add_node(:a, %{})
        |> Yog.add_node(:b, %{})
        |> Yog.add_edge_ensure(:a, :b, 5)

      assert Internal.best_predecessor(graph, :b, %{}) == nil
    end
  end

  describe "compute_dp/3" do
    test "seeds nodes even if they have predecessors" do
      graph =
        Yog.new(:directed)
        |> Yog.add_node(:a, %{})
        |> Yog.add_node(:b, %{})
        |> Yog.add_edge_ensure(:a, :b, 5)

      dp = Internal.compute_dp(graph, [:a, :b], MapSet.new([:b]))
      assert dp[:b] == {0, nil}
    end

    test "omits unreachable nodes when seed_set is present" do
      graph =
        Yog.new(:directed)
        |> Yog.add_node(:a, %{})
        |> Yog.add_node(:b, %{})
        |> Yog.add_node(:c, %{})
        |> Yog.add_edge_ensure(:a, :b, 5)

      dp = Internal.compute_dp(graph, [:a, :b, :c], MapSet.new([:a]))
      assert Map.has_key?(dp, :a)
      assert Map.has_key?(dp, :b)
      refute Map.has_key?(dp, :c)
    end
  end

  describe "find_best_end_path/2" do
    test "returns nil for empty dp" do
      assert Internal.find_best_end_path(%{}) == nil
    end

    test "handles missing candidates" do
      dp = %{a: {10, nil}}
      assert Internal.find_best_end_path(dp, MapSet.new([:b])) == nil
    end
  end

  describe "reconstruct_path/2" do
    test "handles missing end_id" do
      assert Internal.reconstruct_path(%{}, :missing) == [:missing]
    end
  end
end
