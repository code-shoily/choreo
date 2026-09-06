defmodule Choreo.Lab.ThreatModelDSLTest do
  use ExUnit.Case

  doctest Choreo.Lab.DSL.ThreatModel

  import Choreo.Lab.DSL.ThreatModel

  alias Choreo.ThreatModel

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.ThreatModel.taxonomy()

    assert :boundary in taxonomy.boundaries
    assert :external_entity in taxonomy.nodes
    assert :process in taxonomy.nodes
    assert :data_store in taxonomy.nodes
    assert :flow in taxonomy.edges
    assert :encrypted in taxonomy.modifiers
    assert :protocol in taxonomy.options
    assert Choreo.Lab.DSL.ThreatModel.verbs() == taxonomy
  end

  test "builds a threat model with trust boundaries, elements, and flows" do
    model =
      threat_model do
        internet = boundary("Internet", level: 0)
        app = boundary("Application", level: 2)
        data = boundary("Data", level: 3)

        user = external_entity("User", boundary: internet)
        api = process("API Gateway", boundary: app, privilege: :user)
        db = data_store("Tenant DB", boundary: data, sensitivity: :confidential)

        user ~> api |> encrypted("HTTPS request", protocol: :https)
        api ~> db |> flow("Reads tenant config", protocol: :sql)
      end

    assert Enum.sort(ThreatModel.elements(model)) == [:api, :db, :user]
    assert ThreatModel.boundary_of(model, :user) == "internet"
    assert ThreatModel.boundary_of(model, :api) == "app"
    assert ThreatModel.trust_level(model, :db) == 3
    assert Map.get(model.graph.nodes, :api).privilege == :user
    assert Map.get(model.graph.nodes, :db).sensitivity == :confidential

    edges = ThreatModel.edges_with_meta(model)

    assert Enum.any?(edges, fn
             {:user, :api, _weight, meta} -> meta.encrypted == true and meta.protocol == :https
             _other -> false
           end)

    assert Enum.any?(edges, fn
             {:api, :db, _weight, meta} ->
               meta.label == "Reads tenant config" and meta.protocol == :sql

             _other ->
               false
           end)
  end

  test "supports inline constructors and typed edge forms" do
    model =
      threat_model do
        flow user("Browser") ~> api("Gateway"), "Request", protocol: :https
        encrypted(process("Worker") ~> queue("Jobs"), "Publish job")
        unencrypted(worker("Legacy Worker") ~> database("Legacy DB"), "Plain SQL")
      end

    assert Enum.sort(ThreatModel.elements(model)) == [
             :browser,
             :gateway,
             :jobs,
             :legacy_db,
             :legacy_worker,
             :worker
           ]

    edges = ThreatModel.edges_with_meta(model)

    assert Enum.any?(edges, fn
             {:browser, :gateway, _weight, meta} ->
               meta.label == "Request" and meta.protocol == :https

             _other ->
               false
           end)

    assert Enum.any?(edges, fn
             {:worker, :jobs, _weight, meta} -> meta.encrypted == true
             _other -> false
           end)

    assert Enum.any?(edges, fn
             {:legacy_worker, :legacy_db, _weight, meta} -> meta.encrypted == false
             _other -> false
           end)
  end

  test "supports id option while keeping display label" do
    model =
      threat_model do
        public = boundary("Public Internet", id: :internet)
        api = service("Gateway API", id: :gateway, boundary: public)
        store = database("Tenant Database", id: :tenant_db)

        edge api ~> store, with: "SQL", encrypted: true
      end

    assert ThreatModel.boundary_of(model, :gateway) == "internet"
    assert Map.get(model.graph.nodes, :gateway).label == "Gateway API"
    assert Map.get(model.graph.nodes, :tenant_db).label == "Tenant Database"

    assert Enum.any?(ThreatModel.edges_with_meta(model), fn
             {:gateway, :tenant_db, _weight, meta} ->
               meta.label == "SQL" and meta.encrypted == true

             _other ->
               false
           end)
  end

  test "supports edge/3 with label and options" do
    model =
      threat_model do
        api = service("API")
        db = database("DB")

        edge(api ~> db, "queries", encrypted: true, protocol: :sql)
      end

    assert [{:api, :db, "queries", meta}] = ThreatModel.edges_with_meta(model)
    assert meta.label == "queries"
    assert meta.encrypted == true
    assert meta.protocol == :sql
  end

  test "supports standalone node and boundary declarations updating env" do
    model =
      threat_model do
        boundary("internet", level: 0)
        boundary("app", level: 2)

        user("User", boundary: "internet")
        process("API", boundary: "app")

        user ~> api |> encrypted("HTTPS request", protocol: :https)
      end

    assert ThreatModel.boundary_of(model, :user) == "internet"
    assert ThreatModel.boundary_of(model, :api) == "app"
    assert [{:user, :api, "HTTPS request", meta}] = ThreatModel.edges_with_meta(model)
    assert meta.encrypted == true
    assert meta.protocol == :https
  end

  test "supports scoped boundary blocks with automatic boundary inheritance" do
    model =
      threat_model do
        boundary "Internet", level: 0 do
          browser = user("Browser")
        end

        trust_boundary "app_zone", label: "App Zone", level: 2 do
          api = service("API Gateway", privilege: :user)
          worker = worker("Worker")
        end

        zone "data_zone", label: "Data Zone", level: 3 do
          db = db("Postgres", sensitivity: :confidential)
        end

        browser ~> api |> encrypted("HTTPS", protocol: :https)
        api ~> worker |> on("Dispatches job", protocol: :grpc, encrypted: true)
        worker ~> db |> edge("Writes record", protocol: :sql, encrypted: false)
      end

    assert ThreatModel.boundary_of(model, :browser) == "internet"
    assert ThreatModel.boundary_of(model, :api) == "app_zone"
    assert ThreatModel.boundary_of(model, :worker) == "app_zone"
    assert ThreatModel.boundary_of(model, :db) == "data_zone"

    assert ThreatModel.crosses_boundary?(model, :browser, :api)
    refute ThreatModel.crosses_boundary?(model, :api, :worker)
    assert ThreatModel.crosses_boundary?(model, :worker, :db)

    edges = ThreatModel.edges_with_meta(model)
    assert Enum.any?(edges, fn {f, t, _, m} -> f == :browser and t == :api and m.encrypted end)

    assert Enum.any?(edges, fn {f, t, _, m} ->
             f == :api and t == :worker and m.protocol == :grpc
           end)

    assert Enum.any?(edges, fn {f, t, _, m} ->
             f == :worker and t == :db and m.protocol == :sql
           end)
  end

  test "supports rich pipe modifiers and options" do
    model =
      threat_model do
        u = user("User")
        gw = api("Gateway")
        db = database("DB")

        u ~> gw |> on("login", protocol: :https, encrypted: true)
        gw ~> db |> flow(protocol: :sql, encrypted: true)
      end

    edges = ThreatModel.edges_with_meta(model)

    assert Enum.any?(edges, fn {f, t, l, m} ->
             f == :u and t == :gw and l == "login" and m.encrypted
           end)

    assert Enum.any?(edges, fn {f, t, _, m} ->
             f == :gw and t == :db and m.protocol == :sql and m.encrypted
           end)
  end

  test "helper stubs raise outside DSL block" do
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      process("test")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      database("test")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      boundary("test")
    end
  end

  test "raises on unknown boundary variables" do
    assert_raise ArgumentError, ~r/unknown threat-model boundary variable `missing`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.ThreatModel

          threat_model do
            process("API", boundary: missing)
          end
        end
      )
    end
  end

  test "raises on unknown node variables" do
    assert_raise ArgumentError, ~r/unknown threat-model node variable `missing`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.ThreatModel

          threat_model do
            api = process("API")
            api ~> missing
          end
        end
      )
    end
  end

  test "supports edge keywords, typed edges, and raises on unsupported statements" do
    model =
      threat_model do
        u = user("User")
        api = process("API")
        db = database("DB")

        edge u ~> api
        edge u ~> api, "calls"
        edge u ~> api, protocol: :https
        edge(u ~> api, "calls", protocol: :https)

        flow api ~> db
        flow api ~> db, "queries"
        flow api ~> db, protocol: :sql
        flow api ~> db, "queries", protocol: :sql

        encrypted(u ~> api)
        encrypted(u ~> api, "secure call")
      end

    assert %Choreo.ThreatModel{} = model

    assert_raise ArgumentError, ~r/expected threat-model constructor/, fn ->
      Code.eval_string("""
      import Choreo.Lab.DSL.ThreatModel
      threat_model do
        x = 999
      end
      """)
    end

    assert_raise ArgumentError, ~r/unsupported statement in threat-model DSL/, fn ->
      Code.eval_string("""
      import Choreo.Lab.DSL.ThreatModel
      threat_model do
        bad_statement("test")
      end
      """)
    end
  end
end
