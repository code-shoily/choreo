defmodule Choreo.DecisionTreeTest do
  use ExUnit.Case

  doctest Choreo.DecisionTree
  doctest Choreo.DecisionTree.Render.DOT

  alias Choreo.DecisionTree

  describe "new/0" do
    test "creates an empty tree" do
      tree = DecisionTree.new()
      assert DecisionTree.nodes(tree) == []
      assert DecisionTree.root(tree) == nil
    end
  end

  describe "set_root/3" do
    test "sets the root node" do
      tree = DecisionTree.new() |> DecisionTree.set_root(:weather, feature: "weather")
      assert DecisionTree.root(tree) == :weather
      assert Yog.node(tree.graph, :weather).node_type == :root
      assert Yog.node(tree.graph, :weather).feature == "weather"
    end

    test "rejects second root" do
      tree = DecisionTree.new() |> DecisionTree.set_root(:a, feature: "x")

      assert_raise ArgumentError, "Tree already has a root", fn ->
        DecisionTree.set_root(tree, :b, feature: "y")
      end
    end
  end

  describe "add_decision/3" do
    test "adds an internal node" do
      tree = DecisionTree.new() |> DecisionTree.add_decision(:temp, feature: "temp")
      assert :temp in DecisionTree.nodes(tree)
      assert Yog.node(tree.graph, :temp).node_type == :decision
    end
  end

  describe "add_outcome/3" do
    test "adds a leaf node" do
      tree = DecisionTree.new() |> DecisionTree.add_outcome(:play, label: "Play", class: "yes")
      assert :play in DecisionTree.nodes(tree)
      assert Yog.node(tree.graph, :play).node_type == :outcome
      assert Yog.node(tree.graph, :play).class == "yes"
    end

    test "stores probability" do
      tree = DecisionTree.new() |> DecisionTree.add_outcome(:play, probability: 0.95)
      assert Yog.node(tree.graph, :play).probability == 0.95
    end
  end

  describe "branch/4" do
    test "creates a conditional branch" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:color, feature: "color")
        |> DecisionTree.add_outcome(:stop)
        |> DecisionTree.branch(:color, :stop, "red")

      assert Yog.has_edge?(tree.graph, :color, :stop)
      assert DecisionTree.condition(tree, :color, :stop) == "red"
    end

    test "rejects branching to node with existing parent" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.add_outcome(:y)
        |> DecisionTree.branch(:a, :x, "1")

      assert_raise ArgumentError, "Node :x already has a parent", fn ->
        DecisionTree.branch(tree, :y, :x, "2")
      end
    end

    test "rejects cycle" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.branch(:a, :b, "1")

      assert_raise ArgumentError, "Branch would create a cycle", fn ->
        DecisionTree.branch(tree, :b, :a, "2")
      end
    end

    test "rejects missing parent" do
      tree = DecisionTree.new() |> DecisionTree.add_outcome(:x)

      assert_raise ArgumentError, "Parent node :a does not exist", fn ->
        DecisionTree.branch(tree, :a, :x, "1")
      end
    end

    test "rejects missing child" do
      tree = DecisionTree.new() |> DecisionTree.set_root(:a, feature: "a")

      assert_raise ArgumentError, "Child node :x does not exist", fn ->
        DecisionTree.branch(tree, :a, :x, "1")
      end
    end
  end

  describe "outcomes/1" do
    test "returns only leaf nodes" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.add_outcome(:y)
        |> DecisionTree.branch(:a, :b, "1")
        |> DecisionTree.branch(:b, :x, "2")
        |> DecisionTree.branch(:b, :y, "3")

      assert Enum.sort(DecisionTree.outcomes(tree)) == [:x, :y]
    end
  end

  describe "decisions/1" do
    test "returns root and internal decision nodes" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.branch(:a, :b, "1")
        |> DecisionTree.branch(:b, :x, "2")

      assert Enum.sort(DecisionTree.decisions(tree)) == [:a, :b]
    end
  end

  describe "strict options validation" do
    test "set_root/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        DecisionTree.new() |> DecisionTree.set_root(:a, unknown: true)
      end
    end

    test "add_decision/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        DecisionTree.new() |> DecisionTree.add_decision(:a, unknown: true)
      end
    end

    test "add_outcome/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        DecisionTree.new() |> DecisionTree.add_outcome(:a, unknown: true)
      end
    end
  end

  describe "to_dot/2" do
    test "renders a non-empty DOT string" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:color, feature: "color")
        |> DecisionTree.add_outcome(:stop, label: "Stop")
        |> DecisionTree.add_outcome(:go, label: "Go")
        |> DecisionTree.branch(:color, :stop, "red")
        |> DecisionTree.branch(:color, :go, "green")

      dot = DecisionTree.to_dot(tree)
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "color")
      assert String.contains?(dot, "red")
      assert String.contains?(dot, "green")
    end

    test "renders with dark theme" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.branch(:a, :x, "1")

      dot = DecisionTree.to_dot(tree, theme: :dark)
      assert String.contains?(dot, "digraph")
    end
  end
end
