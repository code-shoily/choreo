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

    test "returns empty when no root" do
      assert Analysis.paths_with_conditions(DecisionTree.new()) == []
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

      # :color is the only remaining node (converted to outcome after recursive prune)
      assert DecisionTree.outcomes(pruned) == [:color]
      refute :color in DecisionTree.decisions(pruned)
      # Orphaned leaf nodes and intermediate decisions are removed
      refute :shade in DecisionTree.nodes(pruned)
      refute :stop_light in DecisionTree.nodes(pruned)
      refute :stop_dark in DecisionTree.nodes(pruned)
    end

    test "leaves diverse decisions intact" do
      tree = traffic_light_tree()
      pruned = Analysis.prune_redundant(tree)

      # All outcomes have different classes, no pruning possible
      assert DecisionTree.outcomes(pruned) == DecisionTree.outcomes(tree)
    end

    test "returns empty tree unchanged" do
      assert Analysis.prune_redundant(DecisionTree.new()) == DecisionTree.new()
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

  describe "rules/1" do
    test "extracts if-then rules for each leaf" do
      rules = Analysis.rules(traffic_light_tree())
      assert length(rules) == 3

      stop_rule = Enum.find(rules, fn r -> r.outcome.class == "stop" end)
      assert stop_rule.conditions == %{"color" => "red"}
      assert stop_rule.outcome.label == "Stop"

      go_rule = Enum.find(rules, fn r -> r.outcome.class == "go" end)
      assert go_rule.conditions == %{"color" => "green"}

      slow_rule = Enum.find(rules, fn r -> r.outcome.class == "slow" end)
      assert slow_rule.conditions == %{"color" => "yellow"}
    end

    test "handles nested decision trees" do
      rules = Analysis.rules(nested_tree())
      assert length(rules) == 3

      sunny_rule = Enum.find(rules, fn r -> r.conditions == %{"weather" => "sunny"} end)
      assert sunny_rule.outcome.class == "yes"

      calm_rule =
        Enum.find(rules, fn r -> r.conditions == %{"weather" => "cloudy", "wind" => "calm"} end)

      assert calm_rule.outcome.class == "yes"

      stormy_rule =
        Enum.find(rules, fn r -> r.conditions == %{"weather" => "cloudy", "wind" => "stormy"} end)

      assert stormy_rule.outcome.class == "no"
    end

    test "returns empty for tree with no root" do
      assert Analysis.rules(DecisionTree.new()) == []
    end
  end

  describe "generate_test_cases/1" do
    test "generates feature maps for each leaf path" do
      cases = Analysis.generate_test_cases(traffic_light_tree())
      assert length(cases) == 3
      assert %{"color" => "red"} in cases
      assert %{"color" => "green"} in cases
      assert %{"color" => "yellow"} in cases
    end

    test "generated cases reach the expected outcomes" do
      tree = traffic_light_tree()

      for features <- Analysis.generate_test_cases(tree) do
        assert {:ok, _path, _label} = Analysis.decide(tree, features)
      end
    end

    test "handles nested trees" do
      cases = Analysis.generate_test_cases(nested_tree())
      assert length(cases) == 3
      assert %{"weather" => "sunny"} in cases
      assert %{"weather" => "cloudy", "wind" => "calm"} in cases
      assert %{"weather" => "cloudy", "wind" => "stormy"} in cases
    end

    test "returns empty for tree with no root" do
      assert Analysis.generate_test_cases(DecisionTree.new()) == []
    end
  end

  describe "orphan_nodes/1" do
    test "returns empty for fully connected tree" do
      assert Analysis.orphan_nodes(traffic_light_tree()) == []
      assert Analysis.orphan_nodes(nested_tree()) == []
    end

    test "detects unreachable nodes" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.add_outcome(:y)
        |> DecisionTree.branch(:a, :x, "1")

      assert Analysis.orphan_nodes(tree) == [:y]
    end

    test "returns empty for tree with no root" do
      assert Analysis.orphan_nodes(DecisionTree.new()) == []
    end
  end

  describe "missing_branches/1" do
    test "returns empty when all expected values are covered" do
      tree = traffic_light_tree()

      assert Analysis.missing_branches(tree, %{"color" => ["red", "green", "yellow"]}) == []
    end

    test "reports missing values for a feature" do
      tree = traffic_light_tree()

      assert Analysis.missing_branches(tree, %{"color" => ["red", "green", "blue"]}) == [
               {:color, "color", ["blue"]}
             ]
    end

    test "ignores features not in the expected domain" do
      tree = traffic_light_tree()

      assert Analysis.missing_branches(tree, %{"size" => ["small", "large"]}) == []
    end

    test "handles nested trees" do
      tree = nested_tree()

      missing = Analysis.missing_branches(tree, %{"weather" => ["sunny", "cloudy", "rainy"]})
      assert {:weather, "weather", ["rainy"]} in missing

      missing = Analysis.missing_branches(tree, %{"wind" => ["calm", "stormy", "breezy"]})
      assert {:wind, "wind", ["breezy"]} in missing
    end

    test "returns empty for tree with no root" do
      assert Analysis.missing_branches(DecisionTree.new(), %{"a" => ["1"]}) == []
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

    test "flags orphan nodes" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.add_outcome(:y)
        |> DecisionTree.branch(:a, :x, "1")

      issues = Analysis.validate(tree)
      assert {:warning, "Orphan nodes: [:y]"} in issues
    end

    test "flags multiple parents" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.branch(:a, :x, "1")

      # Manually inject an extra parent edge to :x to test invariant validator
      tree_with_merged = %{tree | graph: Yog.add_edge_ensure(tree.graph, :b, :x, "2")}
      issues = Analysis.validate(tree_with_merged)
      assert {:error, "Node :x has multiple parents: [:a, :b]"} in issues
    end

    test "flags cycle in graph" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.branch(:a, :b, "1")

      # Manually inject a back-edge to create a cycle
      tree_with_cycle = %{tree | graph: Yog.add_edge_ensure(tree.graph, :b, :a, "loop")}
      issues = Analysis.validate(tree_with_cycle)
      assert {:error, "Cycle detected in decision tree"} in issues
    end
  end

  describe "cyclic?/1" do
    test "returns false for acyclic trees" do
      refute Analysis.cyclic?(traffic_light_tree())
      refute Analysis.cyclic?(nested_tree())
    end

    test "returns true when a cycle is present in underlying graph" do
      tree = traffic_light_tree()
      tree_with_cycle = %{tree | graph: Yog.add_edge_ensure(tree.graph, :stop, :color, "back")}
      assert Analysis.cyclic?(tree_with_cycle)
    end
  end

  describe "dead_ends/1" do
    test "returns empty list when all paths reach outcomes" do
      assert Analysis.dead_ends(traffic_light_tree()) == []
      assert Analysis.dead_ends(nested_tree()) == []
    end

    test "returns decision nodes that cannot reach any outcome" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_decision(:b, feature: "b")
        |> DecisionTree.add_decision(:c, feature: "c")
        |> DecisionTree.add_outcome(:x)
        |> DecisionTree.branch(:a, :x, "1")
        |> DecisionTree.branch(:a, :b, "2")
        |> DecisionTree.branch(:b, :c, "3")

      assert Analysis.dead_ends(tree) == [:b, :c]
    end

    test "returns empty for tree with no root" do
      assert Analysis.dead_ends(DecisionTree.new()) == []
    end
  end

  describe "outcome_distribution/1" do
    test "returns frequencies of outcome classes" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:color, feature: "color")
        |> DecisionTree.add_outcome(:stop1, class: "stop")
        |> DecisionTree.add_outcome(:stop2, class: "stop")
        |> DecisionTree.add_outcome(:go, class: "go")
        |> DecisionTree.branch(:color, :stop1, "red")
        |> DecisionTree.branch(:color, :stop2, "dark_red")
        |> DecisionTree.branch(:color, :go, "green")

      assert Analysis.outcome_distribution(tree) == %{"go" => 1, "stop" => 2}
    end

    test "falls back to label or node_id if class is missing" do
      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:a, feature: "a")
        |> DecisionTree.add_outcome(:x, label: "Result X")
        |> DecisionTree.add_outcome(:y)
        |> DecisionTree.branch(:a, :x, "1")
        |> DecisionTree.branch(:a, :y, "2")

      assert Analysis.outcome_distribution(tree) == %{"Result X" => 1, "y" => 1}
    end

    test "returns empty map for tree with no root" do
      assert Analysis.outcome_distribution(DecisionTree.new()) == %{}
    end
  end
end
