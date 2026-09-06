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

  test "supports edge/3 with label and options" do
    map =
      mind_map do
        sys = root("System")
        req = topic("Requirements")
        edge(sys ~> req, "details", [])
      end

    assert map.edge_meta[{:sys, :req}].label == "details"
    assert map.edge_meta[{:sys, :req}].edge_type == :branch
  end

  test "supports typed edge forms with label and options" do
    map =
      mind_map do
        sys = root("System")
        req = topic("Requirements")
        risk = note("Risk")

        branch(sys ~> req, "expands", [])
        associate(req ~> risk, "relates", [])
      end

    assert map.edge_meta[{:sys, :req}].label == "expands"
    assert map.edge_meta[{:sys, :req}].edge_type == :branch
    assert map.edge_meta[{:req, :risk}].label == "relates"
    assert map.edge_meta[{:req, :risk}].edge_type == :associates
  end

  test "standalone node declarations register IDs in scope for subsequent edges" do
    map =
      mind_map do
        root("Core System", id: :core)
        topic("Auth", id: :auth)

        edge core ~> auth, "secures"
      end

    assert Choreo.MindMap.root(map) == :core
    assert map.graph.nodes[:auth].label == "Auth"
    assert map.edge_meta[{:core, :auth}].label == "secures"
  end

  test "supports rich pipe modifiers on edges" do
    map =
      mind_map do
        sys = root("System")
        req = topic("Requirements")
        arch = topic("Architecture")
        risk = note("Risk")

        sys ~> req |> on("includes", [])
        sys ~> arch |> branch("structures", [])
        req ~> risk |> associate("flags", [])
      end

    assert map.edge_meta[{:sys, :req}].label == "includes"
    assert map.edge_meta[{:sys, :req}].edge_type == :branch
    assert map.edge_meta[{:sys, :arch}].label == "structures"
    assert map.edge_meta[{:sys, :arch}].edge_type == :branch
    assert map.edge_meta[{:req, :risk}].label == "flags"
    assert map.edge_meta[{:req, :risk}].edge_type == :associates
  end

  test "autocomplete helper stubs raise outside DSL block" do
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      root("Root")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      topic("Topic")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      subtopic("Subtopic")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      note("Note")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      branch()
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      associate()
    end
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

  test "supports edge keywords, typed edges, and raises on unsupported statements" do
    map =
      mind_map do
        r = root("Root")
        t1 = topic("Topic 1")
        t2 = topic("Topic 2")
        n = note("Note")

        edge r ~> t1
        edge r ~> t1, "branches"
        branch r ~> t2
        branch r ~> t2, "sub"
        associate(t1 ~> n)
        associate(t1 ~> n, "linked")
      end

    assert %Choreo.MindMap{} = map

    assert_raise ArgumentError, ~r/expected mind-map node constructor/, fn ->
      Code.eval_string("""
      import Choreo.Lab.DSL.MindMap
      mind_map do
        x = 999
      end
      """)
    end

    assert_raise ArgumentError, ~r/unsupported statement in mind-map DSL/, fn ->
      Code.eval_string("""
      import Choreo.Lab.DSL.MindMap
      mind_map do
        bad_statement("test")
      end
      """)
    end
  end
end
