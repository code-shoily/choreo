defmodule Choreo.Dataflow.AnalysisTest do
  use ExUnit.Case

  alias Choreo.Dataflow
  alias Choreo.Dataflow.Analysis

  describe "sources/1 and sinks/1" do
    test "identify sources and sinks" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_source(:b)
        |> Dataflow.add_transform(:c)
        |> Dataflow.add_sink(:d)

      assert Enum.sort(Analysis.sources(flow)) == [:a, :b]
      assert Analysis.sinks(flow) == [:d]
    end

    test "return empty when none exist" do
      flow = Dataflow.new() |> Dataflow.add_transform(:x)
      assert Analysis.sources(flow) == []
      assert Analysis.sinks(flow) == []
    end
  end

  describe "cyclic?/1" do
    test "true when cycle exists" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_transform(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)
        |> Dataflow.connect(:c, :b)

      assert Analysis.cyclic?(flow)
    end

    test "false for acyclic pipeline" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      refute Analysis.cyclic?(flow)
    end

    test "false for empty graph" do
      refute Analysis.cyclic?(Dataflow.new())
    end
  end

  describe "topological_sort/1" do
    test "returns order for DAG" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      assert {:ok, order} = Analysis.topological_sort(flow)
      assert Enum.find_index(order, &(&1 == :a)) < Enum.find_index(order, &(&1 == :b))
      assert Enum.find_index(order, &(&1 == :b)) < Enum.find_index(order, &(&1 == :c))
    end

    test "returns error for cyclic graph" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :a)

      assert {:error, :contains_cycle} = Analysis.topological_sort(flow)
    end
  end

  describe "orphan_nodes/1" do
    test "finds unconnected transform" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_transform(:c)
        |> Dataflow.connect(:a, :b)

      assert Analysis.orphan_nodes(flow) == [:c]
    end

    test "returns all nodes when no sources" do
      flow =
        Dataflow.new()
        |> Dataflow.add_transform(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.connect(:a, :b)

      assert Enum.sort(Analysis.orphan_nodes(flow)) == [:a, :b]
    end

    test "empty when all reachable from source" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      assert Analysis.orphan_nodes(flow) == []
    end
  end

  describe "dead_ends/1" do
    test "finds node with no path to sink" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.add_transform(:d)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      assert Analysis.dead_ends(flow) == [:d]
    end

    test "returns all nodes when no sinks" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.connect(:a, :b)

      assert Enum.sort(Analysis.dead_ends(flow)) == [:a, :b]
    end

    test "empty when all can reach sink" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      assert Analysis.dead_ends(flow) == []
    end
  end

  describe "bottlenecks/1" do
    test "finds high fan-in / fan-out nodes" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_source(:b)
        |> Dataflow.add_transform(:hub)
        |> Dataflow.add_sink(:c)
        |> Dataflow.add_sink(:d)
        |> Dataflow.connect(:a, :hub)
        |> Dataflow.connect(:b, :hub)
        |> Dataflow.connect(:hub, :c)
        |> Dataflow.connect(:hub, :d)

      assert :hub in Analysis.bottlenecks(flow)
    end

    test "respects threshold" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      assert Analysis.bottlenecks(flow) == []
      assert Analysis.bottlenecks(flow, threshold: 2) == [:b]
    end
  end

  describe "longest_path/1" do
    test "finds critical path through weighted edges" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_transform(:c)
        |> Dataflow.add_sink(:d)
        |> Dataflow.connect(:a, :b, weight: 10)
        |> Dataflow.connect(:b, :c, weight: 5)
        |> Dataflow.connect(:c, :d, weight: 2)

      assert {:ok, [:a, :b, :c, :d], 17} = Analysis.longest_path(flow)
    end

    test "picks longest among branches" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_transform(:c)
        |> Dataflow.add_sink(:d)
        |> Dataflow.connect(:a, :b, weight: 1)
        |> Dataflow.connect(:a, :c, weight: 1)
        |> Dataflow.connect(:b, :d, weight: 10)
        |> Dataflow.connect(:c, :d, weight: 1)

      assert {:ok, [:a, :b, :d], 11} = Analysis.longest_path(flow)
    end

    test "returns error for cyclic graph" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :a)

      assert :error = Analysis.longest_path(flow)
    end

    test "returns error when no source-to-sink path" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_sink(:b)

      assert :error = Analysis.longest_path(flow)
    end
  end

  describe "simulate/1" do
    test "propagates source rates through pipeline" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a, rate: 100)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      result = Analysis.simulate(flow)
      assert result[:a].out_rate == 100
      assert result[:b].in_rate == 100
      assert result[:b].out_rate == 100
      assert result[:c].in_rate == 100
      assert result[:c].out_rate == 0
    end

    test "sums multiple inputs at merge" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a, rate: 100)
        |> Dataflow.add_source(:b, rate: 200)
        |> Dataflow.add_merge(:m)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :m)
        |> Dataflow.connect(:b, :m)
        |> Dataflow.connect(:m, :c)

      result = Analysis.simulate(flow)
      assert result[:m].in_rate == 300
      assert result[:m].out_rate == 300
      assert result[:c].in_rate == 300
    end

    test "returns empty for cyclic graph" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :a)

      assert Analysis.simulate(flow) == %{}
    end

    test "includes latency_ms in results" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a, rate: 10)
        |> Dataflow.add_transform(:b, latency_ms: 50)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      result = Analysis.simulate(flow)
      assert result[:b].latency_ms == 50
      assert result[:a].latency_ms == 0
    end
  end

  describe "backpressure_points/1" do
    test "finds nodes with inbound flow" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a, rate: 100)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      points = Analysis.backpressure_points(flow)
      assert :b in points
      assert :c in points
      refute :a in points
    end

    test "respects threshold" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a, rate: 10)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      assert Enum.sort(Analysis.backpressure_points(flow, threshold: 5)) == [:b, :c]
      assert Analysis.backpressure_points(flow, threshold: 50) == []
    end
  end

  describe "edges_of_type/2" do
    test "filters edges by path type" do
      flow =
        Dataflow.new()
        |> Dataflow.add_transform(:a)
        |> Dataflow.add_sink(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.add_sink(:d)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.add_error_path(:a, :c)
        |> Dataflow.add_retry_path(:a, :d)

      normal = Analysis.edges_of_type(flow, :normal)
      error = Analysis.edges_of_type(flow, :error)
      retry = Analysis.edges_of_type(flow, :retry)
      dlq = Analysis.edges_of_type(flow, :dead_letter)

      assert length(normal) == 1
      assert length(error) == 1
      assert length(retry) == 1
      assert dlq == []
    end
  end

  describe "validate/1" do
    test "returns empty for well-formed pipeline" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      assert Analysis.validate(flow) == []
    end

    test "flags missing sources and sinks" do
      flow =
        Dataflow.new()
        |> Dataflow.add_transform(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.connect(:a, :b)

      issues = Analysis.validate(flow)
      assert {:error, "No source nodes"} in issues
      assert {:error, "No sink nodes"} in issues
    end

    test "flags cycles" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :a)

      issues = Analysis.validate(flow)
      assert {:error, "Cycle detected in dataflow"} in issues
    end

    test "flags orphans and dead ends" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_sink(:b)
        |> Dataflow.add_transform(:orphan)
        |> Dataflow.add_transform(:dead)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:orphan, :b)
        |> Dataflow.connect(:a, :dead)

      issues = Analysis.validate(flow)
      assert {:warning, "Orphan nodes: [:orphan]"} in issues
      assert {:warning, "Dead-end nodes: [:dead]"} in issues
    end
  end
end
