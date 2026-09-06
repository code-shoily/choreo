defmodule Choreo.DataflowTest do
  use ExUnit.Case

  doctest Choreo.Dataflow
  doctest Choreo.Dataflow.Render.DOT
  doctest Choreo.Dataflow.Render.Mermaid

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

    test "raises on duplicate connection" do
      assert_raise ArgumentError, fn ->
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_transform(:b)
        |> Dataflow.connect(:a, :b, data_type: "x")
        |> Dataflow.connect(:a, :b, data_type: "y")
      end
    end

    test "strict mode raises on missing nodes" do
      assert_raise ArgumentError, ~r/connect\/4 requires both nodes to exist/, fn ->
        Dataflow.new(strict: true)
        |> Dataflow.connect(:missing, :also_missing)
      end
    end

    test "non-strict mode auto-creates missing nodes" do
      flow =
        Dataflow.new()
        |> Dataflow.connect(:a, :b)

      assert :a in Dataflow.nodes(flow)
      assert :b in Dataflow.nodes(flow)
    end
  end

  describe "clusters" do
    test "add_cluster/3" do
      flow =
        Dataflow.new()
        |> Dataflow.add_cluster("ingest", label: "Ingestion")

      assert Dataflow.cluster(flow, "ingest").label == "Ingestion"
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

  describe "strict options validation" do
    test "add_source/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Dataflow.new() |> Dataflow.add_source(:s, unknown: true)
      end
    end

    test "add_sink/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Dataflow.new() |> Dataflow.add_sink(:s, unknown: true)
      end
    end

    test "add_transform/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Dataflow.new() |> Dataflow.add_transform(:t, unknown: true)
      end
    end

    test "connect/4 raises on invalid path_type" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Dataflow.new()
        |> Dataflow.add_source(:a)
        |> Dataflow.add_sink(:b)
        |> Dataflow.connect(:a, :b, path_type: :invalid)
      end
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

  describe "to_mermaid/2" do
    test "renders a non-empty Mermaid string" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:in, label: "Input")
        |> Dataflow.add_transform(:proc, label: "Process")
        |> Dataflow.add_sink(:out, label: "Output")
        |> Dataflow.connect(:in, :proc, data_type: "raw")
        |> Dataflow.connect(:proc, :out, data_type: "result")

      mermaid = Dataflow.to_mermaid(flow)
      assert String.contains?(mermaid, "graph TD")
      assert String.contains?(mermaid, "Input")
      assert String.contains?(mermaid, "Process")
      assert String.contains?(mermaid, "Output")
    end

    test "renders error paths in red" do
      flow =
        Dataflow.new()
        |> Dataflow.add_transform(:a)
        |> Dataflow.add_sink(:b)
        |> Dataflow.add_sink(:c)
        |> Dataflow.connect(:a, :b)
        |> Dataflow.add_error_path(:a, :c)

      mermaid = Dataflow.to_mermaid(flow)
      assert String.contains?(mermaid, "#ef4444")
      assert String.contains?(mermaid, "stroke-dasharray")
    end

    test "renders clusters as subgraphs" do
      flow =
        Dataflow.new()
        |> Dataflow.add_cluster("ingest", label: "Ingestion")
        |> Dataflow.add_source(:in, cluster: "ingest")
        |> Dataflow.add_sink(:out)
        |> Dataflow.connect(:in, :out)

      mermaid = Dataflow.to_mermaid(flow)
      assert String.contains?(mermaid, "subgraph")
      assert String.contains?(mermaid, "Ingestion")
    end

    test "renders with dark theme" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:in)
        |> Dataflow.add_sink(:out)
        |> Dataflow.connect(:in, :out)

      mermaid = Dataflow.to_mermaid(flow, theme: :dark)
      assert String.contains?(mermaid, "graph TD")
    end

    test "renders with all standard themes" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:in)
        |> Dataflow.add_transform(:proc)
        |> Dataflow.add_sink(:out)
        |> Dataflow.connect(:in, :proc)
        |> Dataflow.connect(:proc, :out)

      for theme <- [:default, :dark, :warm, :forest, :ocean] do
        mermaid = Dataflow.to_mermaid(flow, theme: theme)
        assert String.contains?(mermaid, "graph TD"), "Theme #{theme} should produce graph TD"
      end
    end

    test "renders rate on source nodes" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:in, rate: 1000)
        |> Dataflow.add_sink(:out)
        |> Dataflow.connect(:in, :out)

      mermaid = Dataflow.to_mermaid(flow)
      assert String.contains?(mermaid, "1000 evt/s")
    end

    test "renders edge labels with data_type" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:in)
        |> Dataflow.add_sink(:out)
        |> Dataflow.connect(:in, :out, data_type: "metrics")

      mermaid = Dataflow.to_mermaid(flow)
      assert String.contains?(mermaid, "metrics")
    end

    test "protocol implementation works" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:in)
        |> Dataflow.add_sink(:out)
        |> Dataflow.connect(:in, :out)

      mermaid = Choreo.Mermaid.to_mermaid(flow, [])
      assert String.contains?(mermaid, "graph TD")
    end
  end

  describe "hardened edge cases" do
    test "connect/4 implicitly defines missing from/to stages as transform nodes" do
      flow =
        Dataflow.new()
        |> Dataflow.connect(:a, :b, label: "data")

      assert Enum.sort(Dataflow.nodes(flow)) == [:a, :b]
      assert Yog.node(flow.graph, :a).node_type == :transform
      assert Yog.node(flow.graph, :b).node_type == :transform
      assert Yog.node(flow.graph, :a).label == "a"
      assert Yog.node(flow.graph, :b).label == "b"
    end

    test "to_dot/2 handles stage names with spaces and special characters" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source("my source")
        |> Dataflow.add_sink("another-sink!")
        |> Dataflow.connect("my source", "another-sink!", label: "flow")

      dot = Dataflow.to_dot(flow)
      assert String.contains?(dot, "\"my source\"")
      assert String.contains?(dot, "\"another-sink!\"")
    end

    test "to_mermaid/2 handles stage names with spaces and special characters" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source("my source")
        |> Dataflow.add_sink("another-sink!")
        |> Dataflow.connect("my source", "another-sink!", label: "flow")

      mermaid = Dataflow.to_mermaid(flow)
      assert String.contains?(mermaid, "my source")
      assert String.contains?(mermaid, "another-sink!")
    end

    test "to_mermaid/2 handles all themes, node types, path types, and clusters" do
      flow =
        Dataflow.new()
        |> Dataflow.add_cluster("ingest", label: "Ingestion Cluster")
        |> Dataflow.add_source(:src, label: "Event Stream", rate: 500, cluster: "ingest")
        |> Dataflow.add_buffer(:q, label: "Kafka Queue", capacity: 10_000, cluster: "ingest")
        |> Dataflow.add_conditional(:filter,
          label: "Filter Valid?",
          fillcolor: "#abcdef",
          penwidth: 2
        )
        |> Dataflow.add_merge(:merge_point, label: "Stream Join")
        |> Dataflow.add_sink(:dead_sink, label: "DLQ Sink")
        |> Dataflow.connect(:src, :q, path_type: :normal, rate: 500)
        |> Dataflow.connect(:q, :filter, path_type: :retry, label: "poll")
        |> Dataflow.connect(:filter, :merge_point, path_type: :normal, label: "ok", rate: 450)
        |> Dataflow.connect(:filter, :dead_sink, path_type: :error, label: "err")
        |> Dataflow.connect(:merge_point, :dead_sink, path_type: :dead_letter, label: "failed")

      for theme <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
        mermaid =
          Dataflow.to_mermaid(flow,
            theme: theme,
            direction: :lr,
            highlighted_nodes: [:src, :q],
            highlighted_edges: [{:src, :q}]
          )

        assert String.contains?(mermaid, "subgraph")
        assert String.contains?(mermaid, "Ingestion Cluster")
        assert String.contains?(mermaid, "Kafka Queue")
        assert String.contains?(mermaid, "(cap: 10000)")
        assert String.contains?(mermaid, "500 evt/s")
        assert String.contains?(mermaid, "stroke-dasharray")
      end

      # Custom Theme struct and theme/2
      custom_theme = Choreo.Dataflow.Render.Mermaid.theme(:forest, edge_color: "#123456")
      mermaid = Dataflow.to_mermaid(flow, theme: custom_theme)
      assert String.contains?(mermaid, "#123456")
    end

    test "to_dot/2 handles all themes, node attributes, edge types, and highlighting" do
      flow =
        Dataflow.new()
        |> Dataflow.add_cluster("proc", label: "Processing Cluster")
        |> Dataflow.add_source(:src,
          shape: :invhouse,
          fillcolor: "#ff0000",
          fontcolor: "#ffffff",
          style: "bold",
          penwidth: 2.0,
          image: "source.png",
          description: "Incoming Event Source",
          cluster: "proc"
        )
        |> Dataflow.add_buffer(:buf, capacity: 500, cluster: "proc")
        |> Dataflow.add_transform(:xform, label: "Mapper")
        |> Dataflow.add_conditional(:cond, label: "Check")
        |> Dataflow.add_merge(:join, label: "Joiner")
        |> Dataflow.add_sink(:sink, label: "Final Sink")
        |> Dataflow.connect(:src, :buf, path_type: :normal, label: "feed", rate: 200)
        |> Dataflow.connect(:buf, :xform, path_type: :retry, label: "retry_feed")
        |> Dataflow.connect(:xform, :cond, path_type: :error, label: "on_err")
        |> Dataflow.connect(:cond, :join, path_type: :dead_letter, label: "dlq")
        |> Dataflow.connect(:join, :sink)

      for theme <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
        dot =
          Dataflow.to_dot(flow,
            theme: theme,
            highlighted_nodes: [:src],
            highlighted_edges: [{:src, :buf}]
          )

        assert dot =~ "digraph"
        assert dot =~ "Processing Cluster"
        assert dot =~ "tooltip=\"Incoming Event Source\""
      end

      # Custom Theme struct with graph overrides
      theme_struct =
        Choreo.Dataflow.Render.DOT.theme(:ocean,
          node_fontsize: 14,
          graph_rankdir: :lr,
          graph_bgcolor: "#fdfdfd"
        )

      dot_struct = Dataflow.to_dot(flow, theme: theme_struct)
      assert dot_struct =~ "rankdir=LR"
      assert dot_struct =~ "bgcolor=\"#fdfdfd\""
    end
  end
end
