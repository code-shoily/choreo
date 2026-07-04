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
end
