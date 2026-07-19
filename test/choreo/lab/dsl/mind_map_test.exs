defmodule Choreo.Lab.MindMapDSLTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.MindMap

  doctest Choreo.Lab.DSL.MindMap

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.MindMap.taxonomy()

    assert :root in taxonomy.nodes
    assert :topic in taxonomy.nodes
    assert :subtopic in taxonomy.nodes
    assert :note in taxonomy.nodes
    assert :branch in taxonomy.edges
    assert :associate in taxonomy.edges
    assert :association in taxonomy.edges
    assert :on in taxonomy.modifiers
    assert :with in taxonomy.options
    assert Choreo.Lab.DSL.MindMap.verbs() == taxonomy
  end

  test "builds a mind map with variable-bound nodes" do
    map =
      mind_map do
        system = root("System Design")
        requirements = topic("Requirements")
        architecture = topic("Architecture")
        c4 = subtopic("C4")
        risks = note("Open Risks")

        system ~> requirements
        edge system ~> architecture, "explores"
        architecture ~> c4 |> on("uses")
        edge requirements ~> risks, with: "needs review"
      end

    assert Choreo.MindMap.root(map) == :system
    assert map.graph.nodes[:requirements].node_type == :topic
    assert map.graph.nodes[:c4].node_type == :subtopic
    assert map.graph.nodes[:risks].node_type == :note

    assert map.edge_meta[{:system, :requirements}].edge_type == :branch
    assert map.edge_meta[{:system, :architecture}].label == "explores"
    assert map.edge_meta[{:architecture, :c4}].label == "uses"
    assert map.edge_meta[{:requirements, :risks}].label == "needs review"
  end

  test "supports inline node constructors for one-off sketches" do
    map =
      mind_map do
        root("System Design") ~> topic("Requirements")
      end

    assert Choreo.MindMap.root(map) == :system_design
    assert map.graph.nodes[:requirements].label == "Requirements"
    assert [{:system_design, :requirements, 1}] = Choreo.MindMap.edges(map)
  end

  test "supports id option while keeping display label" do
    map =
      mind_map do
        idea = root("System Design", id: :design)
        reqs = topic("Requirements")

        edge idea ~> reqs, "contains"
      end

    assert Choreo.MindMap.root(map) == :design
    assert map.graph.nodes[:design].label == "System Design"
    assert map.edge_meta[{:design, :reqs}].label == "contains"
  end

  test "supports typed association edges" do
    map =
      mind_map do
        idea = root("System Design")
        requirements = topic("Requirements")
        risks = note("Open Risks")
        tradeoffs = note("Tradeoffs")

        idea ~> requirements
        idea ~> risks
        idea ~> tradeoffs
        associate(requirements ~> risks, "drives")
        association(risks ~> tradeoffs, "informs")
        edge tradeoffs ~> requirements, associate: "reframes"
      end

    assert map.edge_meta[{:requirements, :risks}].edge_type == :associates
    assert map.edge_meta[{:requirements, :risks}].label == "drives"
    assert map.edge_meta[{:risks, :tradeoffs}].edge_type == :associates
    assert map.edge_meta[{:risks, :tradeoffs}].label == "informs"
    assert map.edge_meta[{:tradeoffs, :requirements}].edge_type == :associates
    assert map.edge_meta[{:tradeoffs, :requirements}].label == "reframes"
  end

  test "supports association pipe modifier" do
    map =
      mind_map do
        idea = root("System Design")
        api = topic("API")
        auth = topic("Auth")

        idea ~> api
        idea ~> auth
        api ~> auth |> associate("cross-cutting")
      end

    assert map.edge_meta[{:api, :auth}].edge_type == :associates
    assert map.edge_meta[{:api, :auth}].label == "cross-cutting"
  end

  test "raises on unknown node variables" do
    assert_raise ArgumentError, ~r/unknown mind-map node variable `risk`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.MindMap

          mind_map do
            idea = root("System Design")
            idea ~> risk
          end
        end
      )
    end
  end
end
