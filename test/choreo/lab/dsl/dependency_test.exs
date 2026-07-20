defmodule Choreo.Lab.DependencyDSLTest do
  use ExUnit.Case

  doctest Choreo.Lab.DSL.Dependency

  import Choreo.Lab.DSL.Dependency

  alias Choreo.Dependency

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.Dependency.taxonomy()

    assert :application in taxonomy.nodes
    assert :library in taxonomy.nodes
    assert :module in taxonomy.nodes
    assert :cluster in taxonomy.clusters
    assert :uses in taxonomy.edges
    assert :calls in taxonomy.modifiers
    assert :with in taxonomy.options
    assert Choreo.Lab.DSL.Dependency.verbs() == taxonomy
  end

  test "builds a dependency graph with variable-bound clusters, nodes, and edges" do
    deps =
      dependency do
        core = cluster("Core")
        api = application("API Gateway")
        auth = module("Auth", cluster: core)
        contract = interface("Auth Behaviour")
        phoenix = library("Phoenix")

        api ~> phoenix |> uses("HTTP stack")
        api ~> auth |> calls("validates token")
        auth ~> contract |> implements("callbacks")
      end

    assert Enum.sort(Dependency.nodes(deps)) == [:api, :auth, :contract, :phoenix]
    assert deps.clusters["cluster_core"].label == "Core"
    assert Map.get(deps.graph.nodes, :auth).cluster == "cluster_core"
    assert Map.get(deps.graph.nodes, :api).node_type == :application
    assert Map.get(deps.graph.nodes, :phoenix).node_type == :library
    assert Map.get(deps.graph.nodes, :contract).node_type == :interface

    edge_types =
      Enum.map(Dependency.edges_with_meta(deps), fn {_from, _to, _weight, meta} -> meta.type end)

    assert :uses in edge_types
    assert :calls in edge_types
    assert :inherits in edge_types
  end

  test "supports inline constructors for one-off sketches" do
    deps =
      dependency do
        application("API") ~> library("Phoenix") |> uses("framework")
      end

    assert :api in Dependency.nodes(deps)
    assert :phoenix in Dependency.nodes(deps)

    assert [{:api, :phoenix, _weight, meta}] = Dependency.edges_with_meta(deps)
    assert meta.type == :uses
    assert meta.label == "framework"
  end

  test "supports id option while keeping display label" do
    deps =
      dependency do
        api = app("Public API", id: :api)
        auth = component("Auth Module", id: :auth)

        edge api ~> auth, "uses auth"
      end

    assert Map.get(deps.graph.nodes, :api).label == "Public API"
    assert Map.get(deps.graph.nodes, :auth).label == "Auth Module"
    assert [{:api, :auth, _weight, meta}] = Dependency.edges_with_meta(deps)
    assert meta.label == "uses auth"
    assert meta.type == :uses
  end

  test "supports typed edge aliases and keyword edge forms" do
    deps =
      dependency do
        web = application("Web")
        api = service("API")
        auth = module("Auth")
        auth_test = test_suite("Auth Test")
        mox = package("Mox")

        imports(web ~> api, "client")
        edge api ~> auth, calls: "authenticate"
        dev(auth_test ~> mox, "mock dependency")
        depends_on(auth_test ~> auth, "exercises")
      end

    edge_meta = Dependency.edges_with_meta(deps)
    edge_types = Enum.map(edge_meta, fn {_from, _to, _weight, meta} -> meta.type end)
    labels = Enum.map(edge_meta, fn {_from, _to, _weight, meta} -> meta.label end)

    assert :imports in edge_types
    assert :calls in edge_types
    assert :dev in edge_types
    assert :uses in edge_types
    assert "authenticate" in labels
    assert "mock dependency" in labels
  end

  test "supports cluster nesting and aliases" do
    deps =
      dependency do
        backend = layer("Backend")
        core = group("Core", parent: backend)
        auth = module("Auth", cluster: core)

        module("Repo", cluster: core) ~> auth |> uses("domain API")
      end

    assert Map.has_key?(deps.clusters, "cluster_backend")
    assert deps.clusters["cluster_core"].parent == "backend"
    assert Map.get(deps.graph.nodes, :auth).cluster == "cluster_core"
    assert :repo in Dependency.nodes(deps)
  end

  test "raises on unknown node variables" do
    assert_raise ArgumentError, ~r/unknown dependency node variable `repo`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Dependency

          dependency do
            service = module("Service")
            service ~> repo
          end
        end
      )
    end
  end

  test "raises on unknown cluster variables" do
    assert_raise ArgumentError, ~r/unknown dependency cluster variable `core`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Dependency

          dependency do
            module("Auth", cluster: core)
          end
        end
      )
    end
  end
end
