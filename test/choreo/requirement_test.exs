defmodule Choreo.RequirementTest do
  use ExUnit.Case

  alias Choreo.Requirement

  doctest Requirement
  doctest Requirement.Render.DOT
  doctest Requirement.Render.Mermaid

  describe "creation" do
    test "new/0 creates an empty diagram" do
      req = Requirement.new()
      assert %Requirement{} = req
      assert Requirement.nodes(req) == []
      assert req.name == nil
    end

    test "new/1 accepts a name string" do
      req = Requirement.new("Auth v2")
      assert req.name == "Auth v2"
    end

    test "new/1 accepts keyword options" do
      req = Requirement.new(name: "Auth v2")
      assert req.name == "Auth v2"
    end
  end

  describe "node builders" do
    test "add_requirement/3" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:mfa,
          id: "REQ-001",
          text: "MFA required",
          risk: :high,
          verification: :test,
          kind: :functional
        )

      assert :mfa in Requirement.requirements(req)
      data = Requirement.node(req, :mfa)
      assert data.id == "REQ-001"
      assert data.text == "MFA required"
      assert data.risk == :high
      assert data.verification == :test
      assert data.kind == :functional
      assert data.node_type == :requirement
    end

    test "add_requirement/3 defaults" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")

      data = Requirement.node(req, :mfa)
      assert data.risk == :medium
      assert data.verification == :test
      assert data.kind == :requirement
    end

    test "add_component/3" do
      req =
        Requirement.new()
        |> Requirement.add_component(:auth, label: "Auth Service", type: "microservice")

      assert :auth in Requirement.components(req)
      data = Requirement.node(req, :auth)
      assert data.label == "Auth Service"
      assert data.type == "microservice"
      assert data.node_type == :component
    end

    test "add_test/3" do
      req =
        Requirement.new()
        |> Requirement.add_test(:t1, label: "Login test", type: "integration")

      assert :t1 in Requirement.tests(req)
      data = Requirement.node(req, :t1)
      assert data.label == "Login test"
      assert data.node_type == :test
    end

    test "add_stakeholder/3" do
      req =
        Requirement.new()
        |> Requirement.add_stakeholder(:security, label: "Security Team")

      assert :security in Requirement.stakeholders(req)
      data = Requirement.node(req, :security)
      assert data.label == "Security Team"
      assert data.node_type == :stakeholder
    end

    test "node builders raise on invalid options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Requirement.new()
        |> Requirement.add_requirement(:mfa, risk: :unknown)
      end
    end
  end

  describe "relationship builders" do
    test "satisfies/3" do
      req =
        Requirement.new()
        |> Requirement.add_component(:auth)
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
        |> Requirement.satisfies(:auth, :mfa)

      assert [{:auth, :mfa, 1}] = Requirement.edges(req)
      [meta] = req.edge_meta |> Map.values()
      assert meta.type == :satisfies
    end

    test "verifies/3" do
      req =
        Requirement.new()
        |> Requirement.add_test(:t1)
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
        |> Requirement.verifies(:t1, :mfa)

      [meta] = req.edge_meta |> Map.values()
      assert meta.type == :verifies
    end

    test "refines/3" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:parent, id: "P", text: "Parent")
        |> Requirement.add_requirement(:child, id: "C", text: "Child")
        |> Requirement.refines(:child, :parent)

      [meta] = req.edge_meta |> Map.values()
      assert meta.type == :refines
    end

    test "relate/4 with custom type" do
      req =
        Requirement.new()
        |> Requirement.add_component(:auth)
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
        |> Requirement.relate(:auth, :mfa, type: :implements)

      [meta] = req.edge_meta |> Map.values()
      assert meta.type == :implements
      assert meta.label == "implements"
    end

    test "relate/4 with custom label" do
      req =
        Requirement.new()
        |> Requirement.add_component(:auth)
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
        |> Requirement.relate(:auth, :mfa, type: :implements, label: "impl")

      [meta] = req.edge_meta |> Map.values()
      assert meta.label == "impl"
    end

    test "parallel edges are supported" do
      req =
        Requirement.new()
        |> Requirement.add_component(:auth)
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
        |> Requirement.satisfies(:auth, :mfa)
        |> Requirement.traces(:auth, :mfa)

      assert length(Requirement.edges(req)) == 2
    end
  end

  describe "queries" do
    test "nodes/1 returns all node IDs" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:r1, id: "R1", text: "One")
        |> Requirement.add_component(:c1)

      assert Enum.sort(Requirement.nodes(req)) == [:c1, :r1]
    end

    test "edges_with_meta/1" do
      req =
        Requirement.new()
        |> Requirement.add_component(:auth)
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
        |> Requirement.satisfies(:auth, :mfa)

      assert [{:auth, :mfa, 1, meta}] = Requirement.edges_with_meta(req)
      assert meta.type == :satisfies
    end

    test "node/1 returns nil for missing node" do
      assert Requirement.node(Requirement.new(), :missing) == nil
    end
  end

  describe "rendering" do
    test "to_dot/2 produces a DOT string" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
        |> Requirement.add_component(:auth, label: "Auth")
        |> Requirement.satisfies(:auth, :mfa)

      dot = Requirement.to_dot(req)
      assert dot =~ "digraph"
      assert dot =~ "REQ-001"
      assert dot =~ "Auth"
      assert dot =~ "satisfies"
    end

    test "to_mermaid/2 produces requirementDiagram" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
        |> Requirement.add_component(:auth, label: "Auth")
        |> Requirement.satisfies(:auth, :mfa)

      mermaid = Requirement.to_mermaid(req)
      assert mermaid =~ "requirementDiagram"
      assert mermaid =~ "REQ-001"
      assert mermaid =~ "satisfies"
    end

    test "to_mermaid/2 maps depends relationships to traces" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:r1, id: "R1", text: "Req 1")
        |> Requirement.add_requirement(:r2, id: "R2", text: "Req 2")
        |> Requirement.depends(:r1, :r2)

      mermaid = Requirement.to_mermaid(req)
      assert mermaid =~ "r1 - traces -> r2"
    end

    test "to_mermaid/2 renders requirement kinds" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:perf, id: "P1", text: "Perf", kind: :performance)
        |> Requirement.add_requirement(:design,
          id: "D1",
          text: "Design",
          kind: :design_constraint
        )

      mermaid = Requirement.to_mermaid(req)
      assert mermaid =~ "performanceRequirement"
      assert mermaid =~ "designConstraint"
    end

    test "to_mermaid/2 maps critical risk to High" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:r1, id: "R1", text: "Risk", risk: :critical)

      mermaid = Requirement.to_mermaid(req)
      assert mermaid =~ "risk: High"
      assert mermaid =~ "criticalRisk"
    end

    test "themes apply to DOT rendering" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:r1, id: "R1", text: "One")

      dot = Requirement.to_dot(req, theme: :dark)
      assert dot =~ "digraph"
    end
  end

  describe "protocols" do
    test "Choreo.DOT protocol dispatches" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:r1, id: "R1", text: "One")

      assert Choreo.to_dot(req) =~ "digraph"
    end

    test "Choreo.Mermaid protocol dispatches" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:r1, id: "R1", text: "One")

      assert Choreo.to_mermaid(req) =~ "requirementDiagram"
    end

    test "Choreo.Viewable rebuild preserves edge metadata" do
      req =
        Requirement.new()
        |> Requirement.add_component(:auth)
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
        |> Requirement.satisfies(:auth, :mfa)

      new_graph = req.graph
      rebuilt = Choreo.Viewable.rebuild(req, new_graph)
      assert map_size(rebuilt.edge_meta) == 1
    end
  end

  describe "Viewable zoom predicates" do
    test "zoom level 0 only shows top-level requirements" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:parent, id: "P", text: "Parent")
        |> Requirement.add_requirement(:child, id: "C", text: "Child")
        |> Requirement.add_component(:auth)
        |> Requirement.refines(:child, :parent)

      pred = Choreo.Viewable.zoom_predicate(req, 0)
      assert pred.(:parent, Requirement.node(req, :parent))
      refute pred.(:child, Requirement.node(req, :child))
      refute pred.(:auth, Requirement.node(req, :auth))
    end

    test "zoom level 2 shows all node types" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:r1, id: "R1", text: "One")
        |> Requirement.add_component(:auth)

      pred = Choreo.Viewable.zoom_predicate(req, 2)
      assert pred.(:r1, Requirement.node(req, :r1))
      assert pred.(:auth, Requirement.node(req, :auth))
    end
  end

  describe "Mermaid rendering" do
    test "renders all requirement kinds, risks, verification methods, elements, and relations" do
      req =
        Requirement.new("Comprehensive Requirements")
        |> Requirement.add_requirement(:"1_req_func",
          id: "REQ-01",
          text: "Functional with \"quotes\"\nand newlines",
          risk: :low,
          verification: :analysis,
          kind: :functional
        )
        |> Requirement.add_requirement(:req_iface,
          id: "REQ-02",
          text: "Interface spec",
          risk: :medium,
          verification: :inspection,
          kind: :interface
        )
        |> Requirement.add_requirement(:req_perf,
          id: "REQ-03",
          text: "Performance spec",
          risk: :high,
          verification: :demonstration,
          kind: :performance
        )
        |> Requirement.add_requirement(:req_phys,
          id: "REQ-04",
          text: "Physical spec",
          risk: :critical,
          verification: :test,
          kind: :physical
        )
        |> Requirement.add_requirement(:req_const,
          id: "REQ-05",
          text: "Constraint spec",
          kind: :design_constraint
        )
        |> Requirement.add_component(:comp, label: "Core Component", docref: "docs/comp.md")
        |> Requirement.add_test(:test_suite, label: "E2E Test")
        |> Requirement.add_stakeholder(:pm, label: "Product Manager")
        |> Requirement.contains(:"1_req_func", :req_iface)
        |> Requirement.relate(:req_iface, :req_perf, type: :copies)
        |> Requirement.derives(:req_perf, :req_phys)
        |> Requirement.satisfies(:comp, :"1_req_func")
        |> Requirement.verifies(:test_suite, :req_perf)
        |> Requirement.refines(:req_phys, :req_const)
        |> Requirement.traces(:pm, :req_const)
        |> Requirement.depends(:comp, :test_suite)

      mermaid = Requirement.to_mermaid(req, direction: :lr)
      assert mermaid =~ "requirementDiagram"
      assert mermaid =~ "direction LR"
      assert mermaid =~ "functionalRequirement _1_req_func"
      assert mermaid =~ "interfaceRequirement req_iface"
      assert mermaid =~ "performanceRequirement req_perf"
      assert mermaid =~ "physicalRequirement req_phys"
      assert mermaid =~ "designConstraint req_const"
      assert mermaid =~ "element comp"
      assert mermaid =~ "docref: \"docs/comp.md\""
      assert mermaid =~ "- contains ->"
      assert mermaid =~ "- copies ->"
      assert mermaid =~ "- derives ->"
      assert mermaid =~ "- satisfies ->"
      assert mermaid =~ "- verifies ->"
      assert mermaid =~ "- refines ->"
      assert mermaid =~ "- traces ->"
      assert mermaid =~ "class _1_req_func lowRisk"
      assert mermaid =~ "class req_perf highRisk"
    end

    test "supports requirement diagram directions and themes" do
      req =
        Requirement.new("Reqs")
        |> Requirement.add_requirement(:r1, id: "R1", text: "Requirement 1")

      for dir <- [:bt, :rl] do
        dir_mermaid = Requirement.to_mermaid(req, direction: dir)
        assert dir_mermaid =~ "direction #{String.upcase(to_string(dir))}"
      end

      assert %Choreo.Theme{} = Requirement.Render.Mermaid.theme(:default)
    end
  end

  describe "DOT rendering" do
    test "renders all requirement kinds, risks, elements, relations, and themes" do
      req =
        Requirement.new("Comprehensive Requirements")
        |> Requirement.add_requirement(:req_low, id: "R-LOW", text: "Low risk", risk: :low)
        |> Requirement.add_requirement(:req_med, id: "R-MED", text: "Med risk", risk: :medium)
        |> Requirement.add_requirement(:req_high, id: "R-HIGH", text: "High risk", risk: :high)
        |> Requirement.add_requirement(:req_crit,
          id: "R-CRIT",
          text: "Crit risk",
          risk: :critical
        )
        |> Requirement.add_component(:comp, label: "Component Node")
        |> Requirement.add_test(:test_suite, label: "Test Suite")
        |> Requirement.add_stakeholder(:pm, label: "Product Manager")
        |> Requirement.satisfies(:comp, :req_low)
        |> Requirement.verifies(:test_suite, :req_med)
        |> Requirement.refines(:req_high, :req_low)
        |> Requirement.depends(:req_high, :req_med)
        |> Requirement.contains(:req_crit, :req_high)
        |> Requirement.derives(:req_med, :req_low)
        |> Requirement.traces(:pm, :req_crit)

      for dir <- [:tb, :td, :lr, :bt, :rl, :unknown] do
        dot = Requirement.to_dot(req, direction: dir)
        assert dot =~ "digraph"
        assert dot =~ "R-LOW"
        assert dot =~ "R-MED"
        assert dot =~ "R-HIGH"
        assert dot =~ "R-CRIT"
        assert dot =~ "Component Node"
        assert dot =~ "Test Suite"
        assert dot =~ "Product Manager"
      end

      for theme <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
        dot = Requirement.to_dot(req, theme: theme)
        assert dot =~ "digraph"
      end

      custom_theme = Requirement.Render.DOT.theme(:ocean, edge_color: "#abcdef")
      dot = Requirement.to_dot(req, theme: custom_theme)
      assert dot =~ "digraph"
    end
  end
end
