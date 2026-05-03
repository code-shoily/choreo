defmodule Choreo.ViewTest do
  use ExUnit.Case

  doctest Choreo.View

  alias Choreo.MindMap
  alias Choreo.View

  describe "focus/3" do
    test "returns node and direct neighbours with radius 1" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.add_subtopic(:d)
        |> MindMap.add_subtopic(:e)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.branch(:b, :d)
        |> MindMap.branch(:c, :e)

      focused = View.focus(map, :b, radius: 1)

      assert Enum.sort(MindMap.nodes(focused)) == [:a, :b, :d]
      assert MindMap.root(focused) == :a
      assert focused.edge_meta[{:a, :b}]
      assert focused.edge_meta[{:b, :d}]
      refute focused.edge_meta[{:a, :c}]
      refute focused.edge_meta[{:c, :e}]
    end

    test "radius 2 includes second-degree nodes" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_note(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)
        |> MindMap.branch(:c, :d)

      focused = View.focus(map, :a, radius: 2)
      assert Enum.sort(MindMap.nodes(focused)) == [:a, :b, :c]
    end

    test "radius 0 returns only the target node" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.branch(:a, :b)

      focused = View.focus(map, :b, radius: 0)
      assert MindMap.nodes(focused) == [:b]
    end

    test "raises when node does not exist" do
      map = MindMap.new() |> MindMap.set_root(:a)

      assert_raise ArgumentError, "Node :missing does not exist in diagram", fn ->
        View.focus(map, :missing)
      end
    end

    test "picks highest-level remaining node as root when original is excluded" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)

      # Focus on :b with radius 0 — root :a is excluded
      focused = View.focus(map, :b, radius: 0)
      assert MindMap.root(focused) == :b
    end
  end

  describe "focus_between/4" do
    test "returns only shortest path nodes" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.add_subtopic(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.branch(:b, :d)
        |> MindMap.branch(:c, :d)

      # Shortest path from :a to :d is either a->b->d or a->c->d
      path_view = View.focus_between(map, :a, :d)
      nodes = MindMap.nodes(path_view)
      assert :a in nodes
      assert :d in nodes
      assert length(nodes) == 3
    end

    test "includes neighbourhood with radius > 0" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_note(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)
        |> MindMap.branch(:c, :d)

      path_view = View.focus_between(map, :a, :d, radius: 1)
      assert Enum.sort(MindMap.nodes(path_view)) == [:a, :b, :c, :d]
    end

    test "raises when either node is missing" do
      map = MindMap.new() |> MindMap.set_root(:a)

      assert_raise ArgumentError, "Node :missing does not exist in diagram", fn ->
        View.focus_between(map, :a, :missing)
      end

      assert_raise ArgumentError, "Node :missing does not exist in diagram", fn ->
        View.focus_between(map, :missing, :a)
      end
    end

    test "raises when no path exists" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)

      # :c is orphaned — no path from :a to :c

      assert_raise ArgumentError, "No path from :a to :c", fn ->
        View.focus_between(map, :a, :c)
      end
    end
  end

  describe "zoom/2" do
    test "level 0 keeps only root" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_note(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)
        |> MindMap.branch(:c, :d)

      zoomed = View.zoom(map, level: 0)
      assert MindMap.nodes(zoomed) == [:a]
      assert MindMap.root(zoomed) == :a
    end

    test "level 1 keeps root and topics" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.add_subtopic(:d)
        |> MindMap.add_note(:e)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.branch(:b, :d)
        |> MindMap.branch(:d, :e)

      zoomed = View.zoom(map, level: 1)
      assert Enum.sort(MindMap.nodes(zoomed)) == [:a, :b, :c]
      assert MindMap.root(zoomed) == :a
    end

    test "level 2 keeps root, topics, and subtopics" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_note(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)
        |> MindMap.branch(:c, :d)

      zoomed = View.zoom(map, level: 2)
      assert Enum.sort(MindMap.nodes(zoomed)) == [:a, :b, :c]
      assert MindMap.root(zoomed) == :a
    end

    test "level 3 keeps everything" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_note(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)
        |> MindMap.branch(:c, :d)

      zoomed = View.zoom(map, level: 3)
      assert Enum.sort(MindMap.nodes(zoomed)) == [:a, :b, :c, :d]
    end

    test "edge_meta is pruned after zoom" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)

      zoomed = View.zoom(map, level: 1)
      assert map_size(zoomed.edge_meta) == 1
      assert zoomed.edge_meta[{:a, :b}]
      refute zoomed.edge_meta[{:b, :c}]
    end

    test "transitive adds virtual edges through removed zoom levels" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_topic(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)
        |> MindMap.branch(:a, :d)

      # Zoom to level 1 keeps :a, :b, :d. :c is a leaf subtopic, removed.
      # No transitive edge needed since :c was not connecting two kept nodes.
      zoomed = View.zoom(map, level: 1, transitive: true)
      assert Enum.sort(MindMap.nodes(zoomed)) == [:a, :b, :d]
    end
  end

  describe "filter/3" do
    test "keeps only matching nodes" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_note(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)

      filtered = View.filter(map, fn _id, data -> data[:node_type] in [:root, :topic] end)
      assert Enum.sort(MindMap.nodes(filtered)) == [:a, :b]
    end

    test "hides notes" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_note(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)

      filtered = View.filter(map, fn _id, data -> data[:node_type] != :note end)
      assert Enum.sort(MindMap.nodes(filtered)) == [:a, :b]
      assert map_size(filtered.edge_meta) == 1
    end

    test "transitive adds virtual edges when middle nodes are removed" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)

      # Filter out :b; with transitive, a virtual edge a->c is added
      filtered = View.filter(map, fn id, _data -> id != :b end, transitive: true)
      assert Enum.sort(MindMap.nodes(filtered)) == [:a, :c]
      assert Yog.has_edge?(filtered.graph, :a, :c)
    end

    test "uses in-degree as root tiebreaker when original root is removed" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.add_subtopic(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.branch(:b, :d)
        |> MindMap.branch(:c, :d)

      # Filter out :a (the root). Both :b and :c have in-degree 0 now.
      # :b comes first alphabetically, but both are topics with equal priority.
      filtered = View.filter(map, fn id, _data -> id != :a end)
      # Root should be one of the remaining nodes with lowest in-degree
      assert MindMap.root(filtered) in [:b, :c]
    end
  end

  describe "collapse/4" do
    test "aggregates matching nodes and rewires edges" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.add_subtopic(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.branch(:b, :d)
        |> MindMap.branch(:c, :d)

      collapsed = View.collapse(map, fn id, _data -> id in [:b, :c] end, :topics)

      assert Enum.sort(MindMap.nodes(collapsed)) == [:a, :d, :topics]
      assert Yog.has_edge?(collapsed.graph, :a, :topics)
      assert Yog.has_edge?(collapsed.graph, :topics, :d)
      refute Yog.has_edge?(collapsed.graph, :a, :b)
      refute Yog.has_edge?(collapsed.graph, :a, :c)
    end

    test "returns original diagram when no nodes match" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.branch(:a, :b)

      collapsed = View.collapse(map, fn _id, _data -> false end, :agg)
      assert Enum.sort(MindMap.nodes(collapsed)) == [:a, :b]
    end

    test "removes self-loops created during rewire" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :a)

      # Collapsing :a and :b together would create a self-loop; it should be removed
      collapsed = View.collapse(map, fn id, _data -> id in [:a, :b] end, :merged)
      assert MindMap.nodes(collapsed) == [:merged]
      refute Yog.has_edge?(collapsed.graph, :merged, :merged)
    end

    test "aggregate node has custom label and data" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.branch(:a, :b)

      collapsed =
        View.collapse(map, fn id, _data -> id == :b end, :agg,
          label: "Billing System",
          data: %{namespace: "billing"}
        )

      node_data = Yog.node(collapsed.graph, :agg)
      assert node_data.label == "Billing System"
      assert node_data.namespace == "billing"
    end
  end

  describe "virtual edge styling" do
    test "transitive edges are marked as virtual in edge_meta" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)

      filtered = View.filter(map, fn id, _data -> id != :b end, transitive: true)

      assert filtered.edge_meta[{:a, :c}].edge_type == :virtual
    end
  end
end
