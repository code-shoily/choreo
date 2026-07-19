defmodule Choreo.Lab.C4DSLTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.C4

  doctest Choreo.Lab.DSL.C4

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.C4.taxonomy()

    assert :person in taxonomy.nodes
    assert :system in taxonomy.nodes
    assert :container in taxonomy.nodes
    assert :component in taxonomy.nodes
    assert :uses in taxonomy.edges
    assert :calls in taxonomy.edges
    assert :scope in taxonomy.events
    assert :technology in taxonomy.modifiers
    assert Choreo.Lab.DSL.C4.verbs() == taxonomy
  end

  test "builds a C4 model with variable-bound hierarchy and relationships" do
    model =
      c4 do
        customer = person("Customer", description: "API consumer")
        gateway = system("API Gateway", scope: :in, description: "Routes tenant API traffic")
        api = container("Gateway API", parent: gateway, technology: "Phoenix")
        db = database("Tenant DB", parent: gateway, technology: "Postgres")
        auth = component("Auth Controller", parent: api, technology: "Phoenix")

        customer ~> api |> uses("Submits API requests", technology: "HTTPS")
        api ~> auth |> calls("Delegates authentication")
        auth ~> db |> reads("Tenant config", technology: "SQL")
        scope gateway
      end

    assert Choreo.C4.scope(model) == :gateway
    assert model.graph.nodes[:customer].node_type == :person
    assert model.graph.nodes[:gateway].node_type == :software_system
    assert model.graph.nodes[:gateway].scope == :in
    assert model.graph.nodes[:api].node_type == :container
    assert model.graph.nodes[:api].parent == :gateway
    assert model.graph.nodes[:db].node_type == :container
    assert model.graph.nodes[:auth].node_type == :component
    assert model.graph.nodes[:auth].parent == :api

    edges = Choreo.C4.edges_with_meta(model)

    assert Enum.map(edges, fn {from, to, _w, meta} ->
             {from, to, meta.label, meta[:technology]}
           end) == [
             {:customer, :api, "Submits API requests", "HTTPS"},
             {:api, :auth, "Delegates authentication", nil},
             {:auth, :db, "Tenant config", "SQL"}
           ]
  end

  test "supports inline constructors for one-off sketches" do
    model =
      c4 do
        person("Customer") ~> system("Banking") |> uses("Uses")
      end

    assert model.graph.nodes[:customer].node_type == :person
    assert model.graph.nodes[:banking].node_type == :software_system
    assert [{:customer, :banking, 1}] = Choreo.C4.edges(model)
  end

  test "supports id option while keeping display label" do
    model =
      c4 do
        app = system("Internet Banking", id: :banking)
        api = container("API", parent: app)

        edge app ~> api, "Contains runnable API"
        in_scope app
      end

    assert model.graph.nodes[:banking].label == "Internet Banking"
    assert model.graph.nodes[:api].parent == :banking
    assert Choreo.C4.scope(model) == :banking
    assert [{:banking, :api, _weight, meta}] = Choreo.C4.edges_with_meta(model)
    assert meta.label == "Contains runnable API"
  end

  test "supports clusters and parent-derived grouping" do
    model =
      c4 do
        platform = boundary("Platform")
        internal = boundary("Internal Systems", parent: platform)
        gateway = system("API Gateway")
        api = container("API", parent: gateway)
        worker = container("Worker", parent: gateway)

        api ~> worker |> sends("Jobs", technology: "Kafka")
      end

    assert model.clusters["cluster_platform"].label == "Platform"
    assert model.clusters["cluster_internal"].parent == "cluster_platform"
    assert model.graph.nodes[:api].cluster == "cluster_gateway"
    assert model.graph.nodes[:worker].cluster == "cluster_gateway"
    assert [{:api, :worker, _weight, meta}] = Choreo.C4.edges_with_meta(model)
    assert meta.label == "Jobs"
    assert meta.technology == "Kafka"
  end

  test "supports typed keyword edges" do
    model =
      c4 do
        api = service("API", technology: "Phoenix")
        db = datastore("Database", technology: "Postgres")
        queue = container("Events", technology: "Kafka")

        edge api ~> db, reads: "Tenant config"
        edge api ~> queue, publishes: "Audit event"
      end

    labels =
      model
      |> Choreo.C4.edges_with_meta()
      |> Enum.map(fn {_from, _to, _w, meta} -> meta.label end)

    assert labels == ["Tenant config", "Audit event"]
  end

  test "raises on unknown parent variables" do
    assert_raise ArgumentError, ~r/unknown C4 node variable `gateawy` in `parent:`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.C4

          c4 do
            container("API", parent: gateawy)
          end
        end
      )
    end
  end

  test "raises on unknown relationship variables" do
    assert_raise ArgumentError, ~r/unknown C4 node variable `api`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.C4

          c4 do
            user = person("User")
            user ~> api |> uses("Uses")
          end
        end
      )
    end
  end
end
