defmodule Choreo.DecisionTree.ViewTest do
  use ExUnit.Case

  alias Choreo.DecisionTree
  alias Choreo.View

  describe "focus/3" do
    test "shows root and neighbours" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:weather, feature: "weather")
        |> DecisionTree.add_decision(:wind, feature: "wind")
        |> DecisionTree.add_outcome(:play, label: "Play")
        |> DecisionTree.add_outcome(:stay, label: "Stay")
        |> DecisionTree.branch(:weather, :wind, "cloudy")
        |> DecisionTree.branch(:wind, :play, "calm")
        |> DecisionTree.branch(:wind, :stay, "stormy")

      focused = View.focus(tree, :wind, radius: 1)
      nodes = DecisionTree.nodes(focused)

      assert :weather in nodes
      assert :wind in nodes
      assert :play in nodes
      assert :stay in nodes
      assert DecisionTree.root(focused) == :weather
    end
  end

  describe "focus_between/4" do
    test "shows shortest path between root and outcome" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:c, label: "C")
        |> DecisionTree.branch(:a, :b, 1)
        |> DecisionTree.branch(:b, :c, 1)

      path = View.focus_between(tree, :a, :c)
      assert Enum.sort(DecisionTree.nodes(path)) == [:a, :b, :c]
    end
  end

  describe "zoom/2" do
    test "level 0 keeps only root" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:c, label: "C")
        |> DecisionTree.branch(:a, :b, "1")
        |> DecisionTree.branch(:b, :c, "2")

      zoomed = View.zoom(tree, level: 0)
      assert DecisionTree.nodes(zoomed) == [:a]
      assert DecisionTree.root(zoomed) == :a
    end

    test "level 1 keeps root and decisions" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:c, label: "C")
        |> DecisionTree.add_outcome(:d, label: "D")
        |> DecisionTree.branch(:a, :b, "1")
        |> DecisionTree.branch(:b, :c, "2")
        |> DecisionTree.branch(:b, :d, "3")

      zoomed = View.zoom(tree, level: 1)
      assert Enum.sort(DecisionTree.nodes(zoomed)) == [:a, :b]
      assert DecisionTree.root(zoomed) == :a
    end

    test "level 2 keeps everything" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:c, label: "C")
        |> DecisionTree.branch(:a, :b, "1")
        |> DecisionTree.branch(:b, :c, "2")

      zoomed = View.zoom(tree, level: 2)
      assert Enum.sort(DecisionTree.nodes(zoomed)) == [:a, :b, :c]
    end

    test "transitive adds virtual edges through removed outcomes" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:c, label: "C")
        |> DecisionTree.branch(:a, :b, "1")
        |> DecisionTree.branch(:b, :c, "2")

      # Zoom to level 1 removes :c. With transitive, virtual edge a->b remains.
      zoomed = View.zoom(tree, level: 1, transitive: true)
      assert Enum.sort(DecisionTree.nodes(zoomed)) == [:a, :b]
      assert Yog.has_edge?(zoomed.graph, :a, :b)
    end
  end

  describe "filter/3" do
    test "hides outcomes" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:c, label: "C")
        |> DecisionTree.branch(:a, :b, "1")
        |> DecisionTree.branch(:b, :c, "2")

      filtered = View.filter(tree, fn _id, data -> data[:node_type] != :outcome end)
      assert Enum.sort(DecisionTree.nodes(filtered)) == [:a, :b]
    end
  end

  describe "collapse/4" do
    test "aggregates decisions into one node" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_decision(:c, feature: "c")
        |> DecisionTree.add_outcome(:d, label: "D")
        |> DecisionTree.add_outcome(:e, label: "E")
        |> DecisionTree.branch(:a, :b, "1")
        |> DecisionTree.branch(:a, :c, "2")
        |> DecisionTree.branch(:b, :d, "3")
        |> DecisionTree.branch(:c, :e, "4")

      collapsed =
        View.collapse(tree, fn _id, data -> data[:node_type] == :decision end, :decisions)

      assert :decisions in DecisionTree.nodes(collapsed)
      assert :a in DecisionTree.nodes(collapsed)
      assert :d in DecisionTree.nodes(collapsed)
      assert :e in DecisionTree.nodes(collapsed)
      refute :b in DecisionTree.nodes(collapsed)
      refute :c in DecisionTree.nodes(collapsed)

      assert Yog.has_edge?(collapsed.graph, :a, :decisions)
      assert Yog.has_edge?(collapsed.graph, :decisions, :d)
      assert Yog.has_edge?(collapsed.graph, :decisions, :e)
    end
  end

  describe "virtual edge styling" do
    test "transitive edges are marked as virtual" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:c, label: "C")
        |> DecisionTree.branch(:a, :b, "1")
        |> DecisionTree.branch(:b, :c, "2")

      filtered = View.filter(tree, fn id, _data -> id != :b end, transitive: true)

      assert filtered.edge_meta[{:a, :c}].edge_type == :virtual
    end
  end
end
