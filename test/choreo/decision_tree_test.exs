defmodule Choreo.DecisionTreeTest do
  use ExUnit.Case

  doctest Choreo.DecisionTree
  doctest Choreo.DecisionTree.Render.DOT
  doctest Choreo.DecisionTree.Render.Mermaid

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

      assert_raise ArgumentError, "Tree already has root :a", fn ->
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

    test "implicitly registers missing parent node" do
      tree = DecisionTree.new() |> DecisionTree.add_outcome(:x)
      tree = DecisionTree.branch(tree, :a, :x, "1")

      assert :a in DecisionTree.nodes(tree)
      assert Yog.node(tree.graph, :a).node_type == :decision
    end

    test "implicitly registers missing child node" do
      tree = DecisionTree.new() |> DecisionTree.set_root(:a, feature: "a")
      tree = DecisionTree.branch(tree, :a, :x, "1")

      assert :x in DecisionTree.nodes(tree)
      assert Yog.node(tree.graph, :x).node_type == :decision
    end

    test "renders node IDs containing spaces or special characters without syntax errors in DOT" do
      tree = DecisionTree.new() |> DecisionTree.branch("my parent", "my child", "yes")
      dot = DecisionTree.to_dot(tree)

      assert String.contains?(dot, "\"my parent\"")
      assert String.contains?(dot, "\"my child\"")
    end

    test "strict mode raises on missing parent" do
      tree = DecisionTree.new(strict: true) |> DecisionTree.set_root(:a, feature: "a")

      assert_raise ArgumentError, ~r/Parent node :b does not exist/, fn ->
        DecisionTree.branch(tree, :b, :c, "1")
      end
    end

    test "strict mode raises on missing child" do
      tree = DecisionTree.new(strict: true) |> DecisionTree.set_root(:a, feature: "a")

      assert_raise ArgumentError, ~r/Child node :c does not exist/, fn ->
        DecisionTree.branch(tree, :a, :c, "1")
      end
    end

    test "non-strict mode auto-creates missing nodes as decisions" do
      tree = DecisionTree.new() |> DecisionTree.branch(:a, :b, "yes")

      assert :a in DecisionTree.nodes(tree)
      assert :b in DecisionTree.nodes(tree)
      assert Yog.node(tree.graph, :a).node_type == :decision
      assert Yog.node(tree.graph, :b).node_type == :decision
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

  describe "to_mermaid/2" do
    test "renders a non-empty Mermaid string" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:color, feature: "color")
        |> DecisionTree.add_outcome(:stop, label: "Stop")
        |> DecisionTree.add_outcome(:go, label: "Go")
        |> DecisionTree.branch(:color, :stop, "red")
        |> DecisionTree.branch(:color, :go, "green")

      mermaid = DecisionTree.to_mermaid(tree)
      assert String.contains?(mermaid, "graph TD")
      assert String.contains?(mermaid, "color")
      assert String.contains?(mermaid, "red")
      assert String.contains?(mermaid, "green")
    end

    test "renders with dark theme" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.branch(:a, :x, "1")

      mermaid = DecisionTree.to_mermaid(tree, theme: :dark)
      assert String.contains?(mermaid, "graph TD")
    end

    test "renders with all standard themes" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.branch(:a, :b, "yes")
        |> DecisionTree.branch(:b, :x, "no")

      for theme <- [:default, :dark, :warm, :forest, :ocean] do
        mermaid = DecisionTree.to_mermaid(tree, theme: theme)
        assert String.contains?(mermaid, "graph TD"), "Theme #{theme} should produce graph TD"
        assert String.contains?(mermaid, "yes"), "Theme #{theme} should include edge label"
      end
    end

    test "respects direction option" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.branch(:a, :x, "1")

      mermaid_lr = DecisionTree.to_mermaid(tree, direction: :lr)
      assert String.contains?(mermaid_lr, "graph LR")

      mermaid_bt = DecisionTree.to_mermaid(tree, direction: :bt)
      assert String.contains?(mermaid_bt, "graph BT")
    end

    test "protocol implementation works" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.branch(:a, :x, "1")

      mermaid = Choreo.Mermaid.to_mermaid(tree, [])
      assert String.contains?(mermaid, "graph TD")
    end
  end
end
