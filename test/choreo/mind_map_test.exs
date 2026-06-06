defmodule Choreo.MindMapTest do
  use ExUnit.Case

  doctest Choreo.MindMap
  doctest Choreo.MindMap.Render.DOT

  alias Choreo.MindMap

  describe "new/0" do
    test "creates an empty directed graph" do
      map = MindMap.new()
      assert MindMap.nodes(map) == []
      assert MindMap.edges(map) == []
      assert Yog.type(map.graph) == :directed
      assert MindMap.root(map) == nil
    end
  end

  describe "set_root/3" do
    test "sets the root node" do
      map = MindMap.new() |> MindMap.set_root(:idea, label: "Big Idea")
      assert :idea in MindMap.nodes(map)
      assert Yog.node(map.graph, :idea).label == "Big Idea"
      assert Yog.node(map.graph, :idea).node_type == :root
      assert MindMap.root(map) == :idea
    end

    test "raises when root already set" do
      map = MindMap.new() |> MindMap.set_root(:a)

      assert_raise ArgumentError, "Mind map already has a root", fn ->
        MindMap.set_root(map, :b)
      end
    end
  end

  describe "node builders" do
    test "add_topic/3" do
      map = MindMap.new() |> MindMap.add_topic(:t, label: "Topic")
      assert :t in MindMap.nodes(map)
      assert Yog.node(map.graph, :t).node_type == :topic
      assert Yog.node(map.graph, :t).label == "Topic"
    end

    test "add_subtopic/3" do
      map = MindMap.new() |> MindMap.add_subtopic(:s, label: "Subtopic")
      assert :s in MindMap.nodes(map)
      assert Yog.node(map.graph, :s).node_type == :subtopic
      assert Yog.node(map.graph, :s).label == "Subtopic"
    end

    test "add_note/3" do
      map = MindMap.new() |> MindMap.add_note(:n, label: "Note")
      assert :n in MindMap.nodes(map)
      assert Yog.node(map.graph, :n).node_type == :note
      assert Yog.node(map.graph, :n).label == "Note"
    end

    test "node builders accept custom colors and shapes" do
      map =
        MindMap.new()
        |> MindMap.add_topic(:t, fillcolor: "#ff0000", shape: :diamond)

      assert Yog.node(map.graph, :t).fillcolor == "#ff0000"
      assert Yog.node(map.graph, :t).shape == :diamond
    end
  end

  describe "branch/4" do
    test "creates a branch edge" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.branch(:a, :b)

      assert Yog.has_edge?(map.graph, :a, :b)
      assert map.edge_meta[{:a, :b}].edge_type == :branch
    end

    test "branch edge accepts a label" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.branch(:a, :b, label: "leads to")

      assert map.edge_meta[{:a, :b}].label == "leads to"
    end

    test "implicitly registers missing nodes as topic nodes" do
      map =
        MindMap.new()
        |> MindMap.branch(:a, :b)

      assert :a in MindMap.nodes(map)
      assert :b in MindMap.nodes(map)
      assert Yog.node(map.graph, :a).node_type == :topic
      assert Yog.node(map.graph, :b).node_type == :topic
    end
  end

  describe "associate/4" do
    test "creates an associative edge" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.associate(:b, :c)

      assert Yog.has_edge?(map.graph, :b, :c)
      assert map.edge_meta[{:b, :c}].edge_type == :associates
    end

    test "associative edge accepts a label" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.associate(:b, :c, label: "related")

      assert map.edge_meta[{:b, :c}].label == "related"
    end

    test "implicitly registers missing nodes as topic nodes" do
      map =
        MindMap.new()
        |> MindMap.associate(:a, :b)

      assert :a in MindMap.nodes(map)
      assert :b in MindMap.nodes(map)
      assert Yog.node(map.graph, :a).node_type == :topic
      assert Yog.node(map.graph, :b).node_type == :topic
    end
  end

  describe "queries" do
    test "nodes/1 returns all node ids" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)

      assert Enum.sort(MindMap.nodes(map)) == [:a, :b]
    end

    test "edges/1 returns all edges" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.branch(:a, :b)

      assert MindMap.edges(map) == [{:a, :b, 1}]
    end

    test "topics/1 returns only topic nodes" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_note(:d)

      assert MindMap.topics(map) == [:b]
    end

    test "subtopics/1 returns only subtopic nodes" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_note(:d)

      assert MindMap.subtopics(map) == [:c]
    end

    test "notes/1 returns only note nodes" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_note(:d)

      assert MindMap.notes(map) == [:d]
    end

    test "to_graph/1 returns the underlying graph" do
      map = MindMap.new()
      assert MindMap.to_graph(map) == map.graph
    end
  end

  describe "to_dot/2" do
    test "renders a DOT string" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a, label: "A")
        |> MindMap.add_topic(:b, label: "B")
        |> MindMap.branch(:a, :b)

      dot = MindMap.to_dot(map)
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "A")
      assert String.contains?(dot, "B")
    end

    test "renders with dark theme" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a, label: "A")
        |> MindMap.add_topic(:b, label: "B")
        |> MindMap.branch(:a, :b)

      dot = MindMap.to_dot(map, theme: :dark)
      assert String.contains?(dot, "digraph")
    end

    test "renders associative edges as dashed" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.associate(:b, :c, label: "link")

      dot = MindMap.to_dot(map)
      assert String.contains?(dot, "dashed")
    end

    test "renders node IDs containing spaces or special characters without syntax errors" do
      map =
        MindMap.new()
        |> MindMap.branch("my central idea", "my sub topic")

      dot = MindMap.to_dot(map)
      assert String.contains?(dot, "\"my central idea\"")
      assert String.contains?(dot, "\"my sub topic\"")
    end
  end
end
