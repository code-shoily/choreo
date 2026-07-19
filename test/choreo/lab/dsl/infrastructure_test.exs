defmodule Choreo.Lab.InfrastructureDSLTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.Infrastructure

  doctest Choreo.Lab.DSL.Infrastructure

  test "verbs returns the Livebook discovery vocabulary" do
    verbs = Choreo.Lab.DSL.Infrastructure.verbs()

    assert :service in verbs.nodes
    assert :database in verbs.nodes
    assert :~> in verbs.edges
    assert :edge in verbs.edges
    assert :on in verbs.modifiers
    assert :with in verbs.options
  end

  test "builds an infrastructure sketch with variable-bound nodes" do
    system =
      infrastructure do
        client = user("API Client")
        gateway = gateway("API Gateway")
        router = service("Tenant Router")
        policy = service("Policy Engine")
        redis = cache("Redis", kind: :redis)
        tenant_db = database("Tenant Metadata DB", kind: :postgres)
        audit_events = queue("Audit Events", kind: :kafka)
        audit_worker = compute("Audit Worker")
        audit_db = database("Audit Log DB")

        client ~> gateway
        gateway ~> redis |> on("checks quota")
        gateway ~> router |> label("routes request")
        router ~> policy
        router ~> tenant_db
        gateway ~> audit_events |> on("writes audit event")
        audit_events ~> audit_worker
        edge(audit_worker ~> audit_db, with: "persists")
      end

    assert system.graph.nodes[:client].node_type == :user
    assert system.graph.nodes[:gateway].node_type == :load_balancer
    assert system.graph.nodes[:router].label == "Tenant Router"
    assert system.graph.nodes[:redis].kind == :redis
    assert system.graph.nodes[:tenant_db].node_type == :database

    labels = system.edge_meta |> Map.values() |> Enum.map(& &1.label)
    assert "checks quota" in labels
    assert "routes request" in labels
    assert "writes audit event" in labels
    assert "persists" in labels
    assert Enum.count(Choreo.edges(system)) == 8
  end

  test "supports inline constructors for one-off sketches" do
    system =
      infrastructure do
        database("Postgres") ~> cache("Redis") |> on("warms")
      end

    assert system.graph.nodes[:postgres].label == "Postgres"
    assert system.graph.nodes[:redis].node_type == :cache
    assert [{:postgres, :redis, 1}] = Choreo.edges(system)
    assert [meta] = Map.values(system.edge_meta)
    assert meta.label == "warms"
  end

  test "supports id option while keeping display label" do
    system =
      infrastructure do
        api = service("Public API", id: :public_api)
        db = database("Postgres")

        edge(api ~> db, label: "reads")
      end

    assert system.graph.nodes[:public_api].label == "Public API"
    assert [{:public_api, :db, 1}] = Choreo.edges(system)
    assert [meta] = Map.values(system.edge_meta)
    assert meta.label == "reads"
  end

  test "raises on unknown node variables" do
    assert_raise ArgumentError, ~r/unknown infrastructure node variable `db`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Infrastructure

          infrastructure do
            api = service("API")
            api ~> db
          end
        end
      )
    end
  end
end
