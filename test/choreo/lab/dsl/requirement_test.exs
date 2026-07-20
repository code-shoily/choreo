defmodule Choreo.Lab.RequirementDSLTest do
  use ExUnit.Case

  doctest Choreo.Lab.DSL.Requirement

  import Choreo.Lab.DSL.Requirement

  alias Choreo.Requirement

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.Requirement.taxonomy()

    assert :functional in taxonomy.requirements
    assert :component in taxonomy.nodes
    assert :test_case in taxonomy.nodes
    assert :stakeholder in taxonomy.nodes
    assert :satisfies in taxonomy.edges
    assert :verifies in taxonomy.modifiers
    assert :with in taxonomy.options
    assert Choreo.Lab.DSL.Requirement.verbs() == taxonomy
  end

  test "builds a requirements model with variable-bound nodes and traceability edges" do
    model =
      requirements "Auth v2" do
        security = stakeholder("Security Team")
        mfa = functional("Users must authenticate with MFA", id: "REQ-001", risk: :high)
        latency = performance("p95 login latency below 100ms", verification: :analysis)
        auth = component("Auth Service", type: "service")
        mfa_test = test_case("MFA login test", type: "integration")

        security ~> mfa |> traces("owns")
        auth ~> mfa |> satisfies("implements")
        mfa_test ~> mfa |> verifies("proves")
        latency ~> mfa |> depends("after MFA")
      end

    assert model.name == "Auth v2"
    assert Requirement.requirements(model) |> Enum.sort() == [:latency, :mfa]
    assert Requirement.components(model) == [:auth]
    assert Requirement.tests(model) == [:mfa_test]
    assert Requirement.stakeholders(model) == [:security]

    mfa = Requirement.node(model, :mfa)
    assert mfa.id == "REQ-001"
    assert mfa.text == "Users must authenticate with MFA"
    assert mfa.kind == :functional
    assert mfa.risk == :high

    latency = Requirement.node(model, :latency)
    assert latency.id == "LATENCY"
    assert latency.kind == :performance
    assert latency.verification == :analysis

    edge_types =
      Enum.map(Requirement.edges_with_meta(model), fn {_from, _to, _weight, meta} -> meta.type end)

    assert :traces in edge_types
    assert :satisfies in edge_types
    assert :verifies in edge_types
    assert :depends in edge_types
  end

  test "supports inline constructors for one-off sketches" do
    model =
      requirements do
        component("Auth") ~> requirement("MFA", id: "REQ-001") |> satisfies("implements")
      end

    assert :auth in Requirement.components(model)
    assert :mfa in Requirement.requirements(model)
    assert Requirement.node(model, :mfa).text == "MFA"
    assert [{:auth, :mfa, _weight, meta}] = Requirement.edges_with_meta(model)
    assert meta.type == :satisfies
    assert meta.label == "implements"
  end

  test "supports node_id option while keeping human requirement id" do
    model =
      requirements do
        auth_req = req("Authenticate users", node_id: :authn, id: "REQ-AUTH-001")
        api = service("API")

        edge api ~> auth_req, satisfies: "implements"
      end

    assert :authn in Requirement.requirements(model)
    assert Requirement.node(model, :authn).id == "REQ-AUTH-001"
    assert Requirement.node(model, :authn).text == "Authenticate users"
    assert [{:api, :authn, _weight, meta}] = Requirement.edges_with_meta(model)
    assert meta.type == :satisfies
  end

  test "supports typed edge statements and aliases" do
    model =
      requirements do
        parent = requirement("Authentication", id: "REQ-AUTH")
        child = design_constraint("Use OAuth2", id: "REQ-OAUTH")
        source = owner("Product")
        test = verification("OAuth conformance test")

        contains(parent ~> child, "breakdown")
        derives(child ~> source, "derived from")
        verifies(test ~> child, "covers")
        relates source ~> parent, "requests"
      end

    edge_meta = Requirement.edges_with_meta(model)
    edge_types = Enum.map(edge_meta, fn {_from, _to, _weight, meta} -> meta.type end)
    labels = Enum.map(edge_meta, fn {_from, _to, _weight, meta} -> meta.label end)

    assert :contains in edge_types
    assert :derives in edge_types
    assert :verifies in edge_types
    assert :traces in edge_types
    assert "breakdown" in labels
    assert "requests" in labels
  end

  test "raises on unknown node variables" do
    assert_raise ArgumentError, ~r/unknown requirement node variable `missing`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Requirement

          requirements do
            req = requirement("MFA", id: "REQ-001")
            req ~> missing
          end
        end
      )
    end
  end
end
