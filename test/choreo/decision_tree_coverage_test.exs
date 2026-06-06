defmodule Choreo.DecisionTreeCoverageTest do
  use ExUnit.Case
  alias Choreo.DecisionTree

  test "set_root error" do
    tree = DecisionTree.new() |> DecisionTree.set_root(:a)

    assert_raise ArgumentError, "Tree already has a root", fn ->
      DecisionTree.set_root(tree, :b)
    end
  end

  test "branch error cases" do
    _tree =
      DecisionTree.new()
      |> DecisionTree.set_root(:r)
      |> DecisionTree.add_outcome(:o)

    # DecisionTree.new()
    # |> DecisionTree.set_root(:r)
    # |> DecisionTree.add_outcome(:o1)
    # |> DecisionTree.branch(:r, :o1, "v1")
    # |> DecisionTree.add_outcome(:o2)
    # |> DecisionTree.branch(:o1, :o2, "v2") # This should fail because o1 is an outcome
    assert_raise ArgumentError, "Decision trees do not allow outcomes to have children", fn ->
      DecisionTree.new()
      |> DecisionTree.set_root(:r)
      |> DecisionTree.add_outcome(:o1)
      |> DecisionTree.branch(:r, :o1, "v1")
      |> DecisionTree.add_decision(:d2)
      |> DecisionTree.branch(:o1, :d2, "oops")
    end
  end

  test "renderer comprehensive" do
    tree =
      DecisionTree.new()
      |> DecisionTree.set_root(:r, feature: "outlook")
      |> DecisionTree.add_decision(:temp, feature: "temperature")
      |> DecisionTree.add_outcome(:yes, label: "Yes", class: "positive", probability: 0.9)
      |> DecisionTree.branch(:r, :temp, "sunny")
      |> DecisionTree.branch(:temp, :yes, "high")

    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert DecisionTree.to_dot(tree, theme: theme) =~ "digraph"
    end
  end
end
