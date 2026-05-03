defmodule Choreo.DecisionTree.AnalysisTest do
  use ExUnit.Case

  doctest Choreo.DecisionTree.Analysis

  alias Choreo.DecisionTree
  alias Choreo.DecisionTree.Analysis

  def traffic_light_tree do
    DecisionTree.new()
    |> DecisionTree.set_root(:color, feature: "color")
    |> DecisionTree.add_outcome(:stop, label: "Stop", class: "stop")
    |> DecisionTree.add_outcome(:go, label: "Go", class: "go")
    |> DecisionTree.add_outcome(:caution, label: "Caution", class: "slow")
    |> DecisionTree.branch(:color, :stop, "red")
    |> DecisionTree.branch(:color, :go, "green")
    |> DecisionTree.branch(:color, :caution, "yellow")
  end

  def nested_tree do
    DecisionTree.new()
    |> DecisionTree.set_root(:weather, feature: "weather")
    |> DecisionTree.add_decision(:wind, feature: "wind")
    |> DecisionTree.add_outcome(:play_sunny, label: "Play", class: "yes")
    |> DecisionTree.add_outcome(:play_cloudy, label: "Play", class: "yes")
    |> DecisionTree.add_outcome(:stay, label: "Stay Home", class: "no")
    |> DecisionTree.branch(:weather, :wind, "cloudy")
    |> DecisionTree.branch(:weather, :play_sunny, "sunny")
    |> DecisionTree.branch(:wind, :play_cloudy, "calm")
    |> DecisionTree.branch(:wind, :stay, "stormy")
  end

  describe "decide/2" do
    test "follows matching branch to outcome" do
      tree = traffic_light_tree()
      assert {:ok, [:color, :go], "Go"} = Analysis.decide(tree, %{"color" => "green"})
      assert {:ok, [:color, :stop], "Stop"} = Analysis.decide(tree, %{"color" => "red"})
    end

    test "returns error for unknown condition" do
      tree = traffic_light_tree()

      assert {:error, "No branch for 'blue' from node :color"} =
               Analysis.decide(tree, %{"color" => "blue"})
    end

    test "returns error for missing feature" do
      tree = traffic_light_tree()
      assert {:error, _} = Analysis.decide(tree, %{"size" => "big"})
    end

    test "returns error when no root" do
      tree = DecisionTree.new()
      assert {:error, "Tree has no root"} = Analysis.decide(tree, %{})
    end

    test "follows multi-level path" do
      tree = nested_tree()

      assert {:ok, [:weather, :wind, :play_cloudy], "Play"} =
               Analysis.decide(tree, %{"weather" => "cloudy", "wind" => "calm"})

      assert {:ok, [:weather, :wind, :stay], "Stay Home"} =
               Analysis.decide(tree, %{"weather" => "cloudy", "wind" => "stormy"})
    end
  end

  describe "paths/1" do
    test "enumerates all root-to-leaf paths" do
      tree = traffic_light_tree()
      paths = Analysis.paths(tree)
      assert length(paths) == 3
      assert [:color, :stop] in paths
      assert [:color, :go] in paths
      assert [:color, :caution] in paths
    end

    test "returns empty when no root" do
      assert Analysis.paths(DecisionTree.new()) == []
    end
  end

  describe "paths_with_conditions/1" do
    test "includes branch conditions" do
      tree = traffic_light_tree()
      paths = Analysis.paths_with_conditions(tree)

      assert length(paths) == 3

      stop_path = Enum.find(paths, fn {path, _branches} -> :stop in path end)
      assert {[:color, :stop], [{:color, :stop, "red"}]} = stop_path
    end
  end

  describe "depth/1" do
    test "returns 0 for single-node tree" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.branch(:a, :x, "1")

      assert Analysis.depth(tree) == 1
    end

    test "returns max depth for nested tree" do
      tree = nested_tree()
      # weather -> wind -> play/stay = depth 2
      assert Analysis.depth(tree) == 2
    end

    test "returns 0 for empty tree" do
      assert Analysis.depth(DecisionTree.new()) == 0
    end
  end

  describe "breadth/1" do
    test "counts outcome nodes" do
      assert Analysis.breadth(traffic_light_tree()) == 3
      assert Analysis.breadth(nested_tree()) == 3
    end
  end

  describe "feature_importance/1" do
    test "counts feature frequencies" do
      tree = nested_tree()
      importance = Analysis.feature_importance(tree)
      assert importance["weather"] == 1
      assert importance["wind"] == 1
    end

    test "excludes nodes without feature" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a)
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.branch(:a, :x, "1")

      assert Analysis.feature_importance(tree) == %{}
    end
  end

  describe "prune_redundant/1" do
    test "replaces decision with uniform outcome" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:color, feature: "color")
        |> DecisionTree.add_decision(:shade, feature: "shade")
        |> DecisionTree.add_outcome(:stop_light, label: "Stop", class: "stop")
        |> DecisionTree.add_outcome(:stop_dark, label: "Stop", class: "stop")
        |> DecisionTree.branch(:color, :shade, "red")
        |> DecisionTree.branch(:shade, :stop_light, "light")
        |> DecisionTree.branch(:shade, :stop_dark, "dark")

      pruned = Analysis.prune_redundant(tree)

      # :shade should now be an outcome
      assert :shade in DecisionTree.outcomes(pruned)
      refute :shade in DecisionTree.decisions(pruned)
    end

    test "leaves diverse decisions intact" do
      tree = traffic_light_tree()
      pruned = Analysis.prune_redundant(tree)

      # All outcomes have different classes, no pruning possible
      assert DecisionTree.outcomes(pruned) == DecisionTree.outcomes(tree)
    end
  end

  describe "reachable_outcomes/1" do
    test "returns all outcome classes for reachable outcomes" do
      tree = traffic_light_tree()
      outcomes = Analysis.reachable_outcomes(tree)
      assert length(outcomes) == 3
      assert "stop" in outcomes
      assert "go" in outcomes
      assert "slow" in outcomes
    end

    test "returns unique classes only" do
      tree = nested_tree()
      outcomes = Analysis.reachable_outcomes(tree)
      assert length(outcomes) == 2
      assert "yes" in outcomes
      assert "no" in outcomes
    end

    test "returns empty for tree with no root" do
      assert Analysis.reachable_outcomes(DecisionTree.new()) == []
    end
  end

  describe "inconsistent_paths/1" do
    test "returns empty for consistent tree" do
      assert Analysis.inconsistent_paths(traffic_light_tree()) == []
      assert Analysis.inconsistent_paths(nested_tree()) == []
    end

    test "finds paths with contradictory feature checks" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:color, feature: "color")
        |> DecisionTree.add_decision(:shade, feature: "color")
        |> DecisionTree.add_outcome(:stop, label: "Stop")
        |> DecisionTree.add_outcome(:go1, label: "Go")
        |> DecisionTree.add_outcome(:go2, label: "Go")
        |> DecisionTree.branch(:color, :shade, "red")
        |> DecisionTree.branch(:color, :go1, "green")
        |> DecisionTree.branch(:shade, :stop, "dark")
        |> DecisionTree.branch(:shade, :go2, "light")

      inconsistencies = Analysis.inconsistent_paths(tree)
      assert length(inconsistencies) == 2

      paths = Enum.map(inconsistencies, &elem(&1, 0))
      assert [:color, :shade, :stop] in paths
      assert [:color, :shade, :go2] in paths

      features = Enum.flat_map(inconsistencies, &elem(&1, 1))
      assert "color" in features
    end
  end

  describe "validate/1" do
    test "returns empty for valid tree" do
      assert Analysis.validate(traffic_light_tree()) == []
    end

    test "flags missing root" do
      issues = Analysis.validate(DecisionTree.new())
      assert {:error, "Tree has no root"} in issues
    end

    test "flags decision without branches" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.branch(:a, :b, "1")

      issues = Analysis.validate(tree)
      assert {:error, "Decision node :b has no branches"} in issues
    end

    test "flags duplicate conditions" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.add_outcome(:y)
        |> DecisionTree.branch(:a, :x, "same")
        |> DecisionTree.branch(:a, :y, "same")

      issues = Analysis.validate(tree)
      assert {:warning, "Duplicate condition 'same' from node :a"} in issues
    end
  end
end
