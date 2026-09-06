defmodule Choreo.Lab.InfrastructureDSLTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.Infrastructure

  doctest Choreo.Lab.DSL.Infrastructure

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.Infrastructure.taxonomy()

    assert :vpc in taxonomy.clusters
    assert :public_subnet in taxonomy.clusters
    assert :service in taxonomy.nodes
    assert :database in taxonomy.nodes
    assert :~> in taxonomy.edges
    assert :edge in taxonomy.edges
    assert :on in taxonomy.modifiers
    assert :parent in taxonomy.options
    assert :with in taxonomy.options
    assert Choreo.Lab.DSL.Infrastructure.verbs() == taxonomy
  end

  test "builds an infrastructure sketch with variable-bound clusters" do
    system =
      infrastructure do
        prod = vpc("Production VPC")
        public = public_subnet("Public Subnet", parent: prod)
        private = private_subnet("Private Subnet", parent: prod)

        internet = user("Internet")
        alb = gateway("ALB", cluster: public)
        api = service("API", cluster: private)
        db = database("Postgres", cluster: private)

        internet ~> alb |> on("HTTPS")
        alb ~> api |> on("HTTP")
        api ~> db |> on("TCP")
      end

    assert system.clusters["cluster_prod"].cluster_type == :vpc
    assert system.clusters["cluster_prod"].label == "Production VPC"
    assert system.clusters["cluster_public"].cluster_type == :subnet_public
    assert system.clusters["cluster_public"].parent == "cluster_prod"
    assert system.clusters["cluster_private"].cluster_type == :subnet_private
    assert system.clusters["cluster_private"].parent == "cluster_prod"

    assert system.graph.nodes[:alb].cluster == "cluster_public"
    assert system.graph.nodes[:api].cluster == "cluster_private"
    assert system.graph.nodes[:db].cluster == "cluster_private"
  end

  test "supports inline cluster constructors" do
    system =
      infrastructure do
        vpc("Production VPC")
        private = private_subnet("Private Subnet", parent: "production_vpc")
        api = service("API", cluster: private)
        db = database("Postgres", cluster: private)

        api ~> db |> on("TCP")
      end

    assert system.clusters["cluster_production_vpc"].cluster_type == :vpc
    assert system.clusters["cluster_private"].parent == "cluster_production_vpc"
    assert system.graph.nodes[:api].cluster == "cluster_private"
  end

  test "raises on unknown cluster variables" do
    assert_raise ArgumentError, ~r/unknown infrastructure cluster variable `privat`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Infrastructure

          infrastructure do
            api = service("API", cluster: privat)
            db = database("Postgres")
            api ~> db
          end
        end
      )
    end
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
        edge audit_worker ~> audit_db, "persists"
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

        edge api ~> db, "reads"
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

  test "supports security validation checks on DSL output" do
    system =
      infrastructure do
        internet = internet(:gateway)
        subnet = private_subnet("Private Subnet")
        db = managed_db(:postgres, cluster: subnet)

        internet ~> db
      end

    warnings = Choreo.Infrastructure.Analysis.validate(system)
    assert warnings != []

    assert Enum.any?(warnings, fn {severity, msg} ->
             severity == :error and String.contains?(msg, "connected directly to public internet")
           end)
  end

  test "supports nested cluster blocks with automatic cluster and parent inheritance" do
    system =
      infrastructure do
        internet = internet("Internet")

        vpc "vpc_prod", label: "Production VPC" do
          public_subnet "subnet_dmz", label: "Public Subnet (DMZ)" do
            alb = load_balancer("Application LB")
          end

          private_subnet "subnet_app", label: "Private Subnet (App)" do
            api = service("API Service")
            worker = compute("Background Worker")
            rds = managed_db("Postgres RDS")
          end
        end

        s3 = storage("Object Store (S3)")

        internet ~> alb |> on("HTTPS", protocol: :https)
        alb ~> api |> on(protocol: :http)
        edge(api ~> rds, "TCP", protocol: :tcp)
        api ~> worker |> on("Jobs", protocol: :amqp)
        api ~> s3 |> protocol(:https)
        worker ~> rds |> on(protocol: :tcp)
        worker ~> s3 |> protocol(:https)
      end

    assert system.clusters["cluster_vpc_prod"].cluster_type == :vpc
    assert system.clusters["cluster_vpc_prod"].label == "Production VPC"
    assert system.clusters["cluster_subnet_dmz"].cluster_type == :subnet_public
    assert system.clusters["cluster_subnet_dmz"].parent == "cluster_vpc_prod"
    assert system.clusters["cluster_subnet_app"].cluster_type == :subnet_private
    assert system.clusters["cluster_subnet_app"].parent == "cluster_vpc_prod"

    assert system.graph.nodes[:alb][:cluster] == "cluster_subnet_dmz"
    assert system.graph.nodes[:api][:cluster] == "cluster_subnet_app"
    assert system.graph.nodes[:worker][:cluster] == "cluster_subnet_app"
    assert system.graph.nodes[:rds][:cluster] == "cluster_subnet_app"
    assert system.graph.nodes[:s3][:cluster] == nil

    warnings = Choreo.Infrastructure.Analysis.validate(system)
    assert warnings == []

    # Check Choreo.Infrastructure query and render functions on DSL output
    assert :alb in Choreo.Infrastructure.nodes(system)
    assert :api in Choreo.Infrastructure.nodes(system)
    assert length(Choreo.Infrastructure.edges(system)) == 7

    assert Choreo.Infrastructure.to_dot(system) =~ "digraph"
    assert Choreo.Infrastructure.to_mermaid(system) =~ "subgraph"
  end

  test "supports standalone node declarations updating env" do
    system =
      infrastructure do
        internet("Internet")
        load_balancer("ALB", id: :my_alb)

        internet ~> my_alb |> on("HTTPS")
      end

    assert :internet in Map.keys(system.graph.nodes)
    assert :my_alb in Map.keys(system.graph.nodes)
    assert Enum.count(Choreo.edges(system)) == 1
  end

  test "supports pipe modifiers with options, protocol, cost, and edge forms" do
    system =
      infrastructure do
        api = service("API")
        db = database("DB")
        cache = cache("Cache")

        api ~> db |> on("SQL", protocol: :tcp, cost: 2)
        api ~> cache |> edge(protocol: :redis, cost: 1)
      end

    metas = Map.values(system.edge_meta)
    sql_meta = Enum.find(metas, &(&1.label == "SQL"))
    assert sql_meta.protocol == :tcp
    assert sql_meta.cost == 2

    cache_meta = Enum.find(metas, &(&1.protocol == :redis))
    assert cache_meta.cost == 1
  end

  test "helper stubs raise outside DSL block" do
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      vpc("test")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      edge("test")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      on("test")
    end
  end
end
