defmodule Choreo.Dataflow.ViewTest do
  use ExUnit.Case

  alias Choreo.Dataflow
  alias Choreo.View

  describe "focus/3" do
    test "shows node and neighbours" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:sensor, label: "Sensor")
        |> Dataflow.add_transform(:parse, label: "Parse")
        |> Dataflow.add_sink(:db, label: "DB")
        |> Dataflow.connect(:sensor, :parse)
        |> Dataflow.connect(:parse, :db)

      focused = View.focus(flow, :parse, radius: 1)
      nodes = Dataflow.nodes(focused)

      assert :sensor in nodes
      assert :parse in nodes
      assert :db in nodes
    end
  end

  describe "focus_between/4" do
    test "shows shortest path between source and sink" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:a, label: "A")
        |> Dataflow.add_transform(:b, label: "B")
        |> Dataflow.add_sink(:c, label: "C")
        |> Dataflow.connect(:a, :b)
        |> Dataflow.connect(:b, :c)

      path = View.focus_between(flow, :a, :c)
      assert Enum.sort(Dataflow.nodes(path)) == [:a, :b, :c]
    end
  end

  describe "zoom/2" do
    test "level 0 keeps only sources and sinks" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:src, label: "Source")
        |> Dataflow.add_transform(:t, label: "Transform")
        |> Dataflow.add_buffer(:buf, label: "Buffer")
        |> Dataflow.add_sink(:sink, label: "Sink")
        |> Dataflow.connect(:src, :t)
        |> Dataflow.connect(:t, :buf)
        |> Dataflow.connect(:buf, :sink)

      zoomed = View.zoom(flow, level: 0)
      assert Enum.sort(Dataflow.nodes(zoomed)) == [:sink, :src]
    end

    test "level 1 keeps sources, sinks, and transforms" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:src, label: "Source")
        |> Dataflow.add_transform(:t, label: "Transform")
        |> Dataflow.add_buffer(:buf, label: "Buffer")
        |> Dataflow.add_sink(:sink, label: "Sink")
        |> Dataflow.connect(:src, :t)
        |> Dataflow.connect(:t, :buf)
        |> Dataflow.connect(:buf, :sink)

      zoomed = View.zoom(flow, level: 1)
      assert Enum.sort(Dataflow.nodes(zoomed)) == [:sink, :src, :t]
    end

    test "level 2 keeps everything" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:src, label: "Source")
        |> Dataflow.add_transform(:t, label: "Transform")
        |> Dataflow.add_buffer(:buf, label: "Buffer")
        |> Dataflow.add_sink(:sink, label: "Sink")
        |> Dataflow.connect(:src, :t)
        |> Dataflow.connect(:t, :buf)
        |> Dataflow.connect(:buf, :sink)

      zoomed = View.zoom(flow, level: 2)
      assert Enum.sort(Dataflow.nodes(zoomed)) == [:buf, :sink, :src, :t]
    end

    test "transitive adds virtual edges through removed buffers" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:src, label: "Source")
        |> Dataflow.add_transform(:t, label: "Transform")
        |> Dataflow.add_buffer(:buf, label: "Buffer")
        |> Dataflow.add_sink(:sink, label: "Sink")
        |> Dataflow.connect(:src, :t)
        |> Dataflow.connect(:t, :buf)
        |> Dataflow.connect(:buf, :sink)

      # Zoom to level 1 removes :buf. With transitive, virtual edge t->sink is added.
      zoomed = View.zoom(flow, level: 1, transitive: true)
      assert :buf not in Dataflow.nodes(zoomed)
      assert Yog.has_edge?(zoomed.graph, :t, :sink)
    end
  end

  describe "filter/3" do
    test "hides buffers" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:src, label: "Source")
        |> Dataflow.add_transform(:t, label: "Transform")
        |> Dataflow.add_buffer(:buf, label: "Buffer")
        |> Dataflow.add_sink(:sink, label: "Sink")
        |> Dataflow.connect(:src, :t)
        |> Dataflow.connect(:t, :buf)
        |> Dataflow.connect(:buf, :sink)

      filtered = View.filter(flow, fn _id, data -> data[:node_type] != :buffer end)
      assert :buf not in Dataflow.nodes(filtered)
      assert :src in Dataflow.nodes(filtered)
      assert :sink in Dataflow.nodes(filtered)
    end
  end

  describe "collapse/4" do
    test "aggregates transforms into one node" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:src, label: "Source")
        |> Dataflow.add_transform(:t1, label: "T1")
        |> Dataflow.add_transform(:t2, label: "T2")
        |> Dataflow.add_sink(:sink, label: "Sink")
        |> Dataflow.connect(:src, :t1)
        |> Dataflow.connect(:t1, :t2)
        |> Dataflow.connect(:t2, :sink)

      collapsed =
        View.collapse(flow, fn _id, data -> data[:node_type] == :transform end, :processing)

      assert :processing in Dataflow.nodes(collapsed)
      assert :src in Dataflow.nodes(collapsed)
      assert :sink in Dataflow.nodes(collapsed)
      refute :t1 in Dataflow.nodes(collapsed)
      refute :t2 in Dataflow.nodes(collapsed)

      assert Yog.has_edge?(collapsed.graph, :src, :processing)
      assert Yog.has_edge?(collapsed.graph, :processing, :sink)
    end
  end

  describe "virtual edge styling" do
    test "transitive edges are marked as virtual" do
      flow =
        Dataflow.new()
        |> Dataflow.add_source(:src, label: "Source")
        |> Dataflow.add_transform(:t, label: "Transform")
        |> Dataflow.add_sink(:sink, label: "Sink")
        |> Dataflow.connect(:src, :t)
        |> Dataflow.connect(:t, :sink)

      filtered = View.filter(flow, fn id, _data -> id != :t end, transitive: true)

      assert filtered.edge_meta[{:src, :sink}].path_type == :virtual
    end
  end
end
