defmodule Choreo.Lab.DecisionTreeDSLTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.DecisionTree

  doctest Choreo.Lab.DSL.DecisionTree

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.DecisionTree.taxonomy()

    assert :root in taxonomy.nodes
    assert :decision in taxonomy.nodes
    assert :outcome in taxonomy.nodes
    assert :branch in taxonomy.edges
    assert :when_ in taxonomy.modifiers
    assert :feature in taxonomy.options
    assert Choreo.Lab.DSL.DecisionTree.verbs() == taxonomy
  end

  test "builds a decision tree with variable-bound nodes" do
    tree =
      decision_tree do
        traffic = root("Traffic Source", feature: "source")
        authenticated = decision("Authenticated?", feature: "auth")
        reject = outcome("Reject", class: "403")
        route = outcome("Route Request", class: "route")

        traffic ~> authenticated |> when_("api")
        edge authenticated ~> reject, "no"
        branch authenticated ~> route, "yes"
      end

    assert Choreo.DecisionTree.root(tree) == :traffic
    assert Yog.node(tree.graph, :traffic).node_type == :root
    assert Yog.node(tree.graph, :traffic).feature == "source"
    assert Yog.node(tree.graph, :authenticated).node_type == :decision
    assert Yog.node(tree.graph, :reject).node_type == :outcome
    assert Yog.node(tree.graph, :reject).class == "403"

    assert Choreo.DecisionTree.condition(tree, :traffic, :authenticated) == "api"
    assert Choreo.DecisionTree.condition(tree, :authenticated, :reject) == "no"
    assert Choreo.DecisionTree.condition(tree, :authenticated, :route) == "yes"
  end

  test "supports inline constructors for one-off sketches" do
    tree =
      decision_tree do
        root("Cache Hit?", feature: "cache_hit")
        ~> outcome("Serve Cache", class: "cache")
        |> when_("yes")
      end

    assert Choreo.DecisionTree.root(tree) == :cache_hit
    assert Yog.node(tree.graph, :serve_cache).node_type == :outcome
    assert Choreo.DecisionTree.condition(tree, :cache_hit, :serve_cache) == "yes"
  end

  test "supports id option while keeping display label" do
    tree =
      decision_tree do
        entry = root("Traffic Source", id: :source)
        api = result("Route API", id: :route_api, class: "api")

        edge entry ~> api, condition: "api"
      end

    assert Choreo.DecisionTree.root(tree) == :source
    assert Yog.node(tree.graph, :source).label == "Traffic Source"
    assert Yog.node(tree.graph, :route_api).label == "Route API"
    assert Choreo.DecisionTree.condition(tree, :source, :route_api) == "api"
  end

  test "supports condition aliases" do
    tree =
      decision_tree do
        eligible = root("Eligible?", feature: "eligible")
        manual = question("Manual Review?", feature: "manual_review")
        accept = leaf("Accept", class: "accept")
        reject = leaf("Reject", class: "reject")

        eligible ~> manual |> condition("maybe")
        manual ~> accept |> on("approved")
        edge manual ~> reject, with: "denied"
      end

    assert Choreo.DecisionTree.condition(tree, :eligible, :manual) == "maybe"
    assert Choreo.DecisionTree.condition(tree, :manual, :accept) == "approved"
    assert Choreo.DecisionTree.condition(tree, :manual, :reject) == "denied"
  end

  test "raises on missing branch condition" do
    assert_raise ArgumentError, ~r/branches require a condition/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.DecisionTree

          decision_tree do
            a = root("A")
            b = outcome("B")
            a ~> b
          end
        end
      )
    end
  end

  test "supports edge/3 and branch/3 with condition and opts" do
    tree =
      decision_tree do
        a = root("A", feature: "a")
        b = outcome("B")
        c = outcome("C")

        edge(a ~> b, "yes", probability: 0.8)
        branch(a ~> c, "no", probability: 0.2)
      end

    assert Choreo.DecisionTree.condition(tree, :a, :b) == "yes"
    assert Choreo.DecisionTree.condition(tree, :a, :c) == "no"
    assert tree.edge_meta[{:a, :b}].probability == 0.8
    assert tree.edge_meta[{:a, :c}].probability == 0.2
  end

  test "supports atom condition and pipe modifiers with options" do
    tree =
      decision_tree do
        a = root("A", feature: "a")
        b = outcome("B")
        c = outcome("C")

        a ~> b |> when_(:yes, weight: 10)
        edge(a ~> c, :no)
      end

    assert Choreo.DecisionTree.condition(tree, :a, :b) == "yes"
    assert Choreo.DecisionTree.condition(tree, :a, :c) == "no"
    assert tree.edge_meta[{:a, :b}].weight == 10
  end

  test "supports standalone node declarations updating variable scope" do
    tree =
      decision_tree do
        root("Weather", feature: "weather")
        decision("Wind", feature: "wind")
        outcome("Play")
        outcome("Stay")

        weather ~> play |> when_("sunny")
        weather ~> wind |> when_("windy")
        wind ~> stay |> when_("strong")
      end

    assert :weather in Choreo.DecisionTree.nodes(tree)
    assert :wind in Choreo.DecisionTree.nodes(tree)
    assert :play in Choreo.DecisionTree.nodes(tree)
    assert :stay in Choreo.DecisionTree.nodes(tree)
    assert Choreo.DecisionTree.condition(tree, :weather, :play) == "sunny"
    assert Choreo.DecisionTree.condition(tree, :weather, :wind) == "windy"
    assert Choreo.DecisionTree.condition(tree, :wind, :stay) == "strong"
  end

  test "autocomplete helper stubs raise outside DSL block" do
    assert_raise RuntimeError,
                 ~r/DSL constructor `when_` must be called inside a DSL block/,
                 fn ->
                   when_("yes")
                 end

    assert_raise RuntimeError,
                 ~r/DSL constructor `condition` must be called inside a DSL block/,
                 fn ->
                   condition("yes")
                 end

    assert_raise RuntimeError, ~r/DSL constructor `edge` must be called inside a DSL block/, fn ->
      edge(:a, :b)
    end
  end

  test "raises on unknown node variables" do
    assert_raise ArgumentError, ~r/unknown decision-tree node variable `b`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.DecisionTree

          decision_tree do
            a = root("A")
            a ~> b |> when_("yes")
          end
        end
      )
    end
  end
end
