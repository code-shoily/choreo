defmodule Choreo.DataflowTest do
  use ExUnit.Case

  alias Choreo.Dataflow

  describe "new/0" do
    test "creates an empty directed graph" do
      flow = Dataflow.new()
      assert Dataflow.nodes(flow) == []
      assert Dataflow.edges(flow) == []
      assert Yog.type(flow.graph) == :directed
    end
  end

  describe "node builders" do
    test "add_source/3" do
      flow = Dataflow.new() |> Dataflow.add_source(:s, label: "Sensor")
      assert :s in Dataflow.nodes(flow)
      assert Yog.node(flow.graph, :s).label == "Sensor"
      assert Yog.node(flow.graph, :s).node_type == :source
    end

    test "add_sink/3" do
      flow = Dataflow.new() |> Dataflow.add_sink(:out, label: "DB")
      assert :out in Dataflow.nodes(flow)
      assert Yog.node(flow.graph, :out).node_type == :sink
    end

    test "add_transform/3" do
      flow = Dataflow.new() |> Dataflow.add_transform(:t, label: "Map")
      assert :t in Dataflow.nodes(flow)
      assert Yog.node(flow.graph, :t).node_type == :transform
    end

    test "add_buffer/3 with capacity" do
      flow = Dataflow.new() |> Dataflow.add_buffer(:q, label: "Queue", capacity: 1000)
      assert :q in Dataflow.nodes(flow)
      assert Yog.node(flow.graph, :q).node_type == :buffer
      assert Yog.node(flow.graph, :q).capacity == 1000
    end

    test "add_conditional/3" do
      flow = Dataflow.new() |> Dataflow.add_conditional(:c, label: "If valid")
      assert :c in Dataflow.nodes(flow)
      assert Yog.node(flow.graph, :c).node_type == :conditional
    end

    test "add_merge/3" do
      flow = Dataflow.new() |> Dataflow.add_merge(:m, label: "Join")
      assert :m in Dataflow.nodes(flow)
      assert Yog.node(flow.graph, :m).node_type == :merge
    end

    test "node builders accept rate and latency_ms" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:src, rate: 100)
        |> Dataflow.add_transform(:proc, latency_ms: 50)

      assert Yog.node(flow.graph, :src).rate == 100
      assert Yog.node(flow.graph, :proc).latency_ms == 50
    end
  end

  describe "connect/4" do
    test "creates a labeled edge" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.connect(:a, :b, data_type: "event")

      assert Yog.has_edge?(flow.graph, :a, :b)
      assert flow.edge_meta[{:a, :b}].label == "event"
      assert flow.edge_meta[{:a, :b}].path_type == :normal
    end

    test "uses explicit label over data_type" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.connect(:a, :b, data_type: "event", label: "custom")

      assert flow.edge_meta[{:a, :b}].label == "custom"
    end

    test "stores custom weight" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.connect(:a, :b, weight: 42)

      assert {_from, _to, 42} = Dataflow.edges(flow) |> List.first()
    end

    test "error path type" do
      flow =
        Dataflow.new()
        |> Dataflow.add_transform(:a)
        |> Dataflow.add_sink(:b)
        |> Dataflow.add_error_path(:a, :b)

      assert flow.edge_meta[{:a, :b}].path_type == :error
    end

    test "retry path type" do
      flow =
        Dataflow.new()
        |> Dataflow.add_transform(:a)
        |> Dataflow.add_sink(:b)
        |> Dataflow.add_retry_path(:a, :b)

      assert flow.edge_meta[{:a, :b}].path_type == :retry
    end

    test "dead letter path type" do
      flow =
        Dataflow.new()
        |> Dataflow.add_transform(:a)
        |> Dataflow.add_sink(:b)
        |> Dataflow.add_dead_letter_path(:a, :b)

      assert flow.edge_meta[{:a, :b}].path_type == :dead_letter
    end
  end

  describe "clusters" do
    test "add_cluster/3" do
      flow =
        Dataflow.new()
        |> Dataflow.add_cluster("ingest", label: "Ingestion")

      assert flow.clusters["cluster_ingest"].label == "Ingestion"
    end

    test "nodes can belong to clusters" do
      flow =
        Dataflow.new()
        |> Dataflow.add_cluster("ingest")
        |> Dataflow.add_source(:sensor, cluster: "ingest")

      assert Yog.node(flow.graph, :sensor).cluster == "cluster_ingest"
    end

    test "cluster prefix is auto-added" do
      flow =
        Dataflow.new()
        |> Dataflow.add_cluster("cluster_ingest")
        |> Dataflow.add_source(:sensor, cluster: "cluster_ingest")

      assert Yog.node(flow.graph, :sensor).cluster == "cluster_ingest"
    end
  end

  describe "nodes_of_type/2" do
    test "filters by node type" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_source(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.add_transform(:d)

      assert Enum.sort(Dataflow.nodes_of_type(flow, :source)) == [:a, :b]
      assert Dataflow.nodes_of_type(flow, :sink) == [:c]
      assert Dataflow.nodes_of_type(flow, :transform) == [:d]
      assert Dataflow.nodes_of_type(flow, :buffer) == []
    end
  end

  describe "to_dot/2" do
    test "renders a non-empty DOT string" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:in, label: "Input")
        |> Dataflow.add_transform(:proc, label: "Process")
        |> Dataflow.add_sink(:out, label: "Output")
        |> Dataflow.connect(:in, :proc, data_type: "raw")
        |> Dataflow.connect(:proc, :out, data_type: "result")

      dot = Dataflow.to_dot(flow)
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "Input")
      assert String.contains?(dot, "Process")
      assert String.contains?(dot, "Output")
    end

    test "renders error paths in red" do
      flow =
        Dataflow.new()
        |> Dataflow.add_transform(:a)
        |> Dataflow.add_sink(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.add_error_path(:a, :c)

      dot = Dataflow.to_dot(flow)
      assert String.contains?(dot, "#ef4444")
      assert String.contains?(dot, "dashed")
    end

    test "renders clusters" do
      flow =
        Dataflow.new()
        |> Dataflow.add_cluster("ingest", label: "Ingestion")
        |> Dataflow.add_source(:in, cluster: "ingest")
        |> Dataflow.add_sink(:out)
        |> Dataflow.connect(:in, :out)

      dot = Dataflow.to_dot(flow)
      assert String.contains?(dot, "subgraph cluster_ingest")
      assert String.contains?(dot, "label=\"Ingestion\"")
    end

    test "renders with dark theme" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:in)
        |> Dataflow.add_sink(:out)
        |> Dataflow.connect(:in, :out)

      dot = Dataflow.to_dot(flow, theme: :dark)
      assert String.contains?(dot, "digraph")
    end

    test "renders rate on source nodes" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:in, rate: 1000)
        |> Dataflow.add_sink(:out)
        |> Dataflow.connect(:in, :out)

      dot = Dataflow.to_dot(flow)
      assert String.contains?(dot, "1000 evt/s")
    end
  end
end
