defmodule Choreo.Lab.CompositionTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.FSM
  import Choreo.Lab.DSL.Infrastructure

  alias Choreo.Lab.Compose
  alias Choreo.Lab.View

  test "composes infrastructure and FSM sketches through embed and trace" do
    auth_fsm =
      fsm do
        unauthenticated = initial("Unauthenticated")
        authenticated = state("Authenticated")
        denied = final("Denied")

        unauthenticated ~> authenticated |> on("valid token")
        edge unauthenticated ~> denied, "invalid token"
      end

    infra =
      infrastructure do
        client = user("API Client")
        gateway = gateway("API Gateway")
        auth = service("Auth Service")
        db = database("Users DB")

        client ~> gateway |> on("calls")
        gateway ~> auth |> on("validates token")
        auth ~> db |> on("loads user")
      end

    system =
      Choreo.new()
      |> Compose.cluster("system", label: "API Gateway System")
      |> Compose.embed(infra, into: "system", as: :infra)
      |> Compose.embed(auth_fsm, into: "system", as: :auth)
      |> Compose.trace(:infra_auth, :auth_unauthenticated, :executes)
      |> Compose.trace(:auth_authenticated, :infra_db, :stores)

    nodes = Choreo.nodes(system)

    assert Map.has_key?(nodes, :infra_gateway)
    assert Map.has_key?(nodes, :infra_auth)
    assert Map.has_key?(nodes, :auth_unauthenticated)
    assert Map.has_key?(nodes, :auth_authenticated)
    assert nodes[:infra_gateway].cluster == "cluster_system"
    assert nodes[:auth_unauthenticated].cluster == "cluster_system"

    path_view = View.between(system, :infra_gateway, :auth_authenticated)

    assert Enum.sort(Map.keys(Choreo.nodes(path_view))) == [
             :auth_authenticated,
             :auth_unauthenticated,
             :infra_auth,
             :infra_gateway
           ]

    trace_edges =
      system
      |> Choreo.edges_with_meta()
      |> Enum.filter(fn {_from, _to, _weight, meta} -> meta[:edge_type] == :trace end)

    assert length(trace_edges) == 2
  end
end
