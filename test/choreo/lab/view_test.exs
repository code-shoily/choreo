defmodule Choreo.Lab.ViewTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.Infrastructure

  alias Choreo.Lab.View

  doctest Choreo.Lab.View

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = View.taxonomy()

    assert :zoom in taxonomy.transforms
    assert :focus in taxonomy.transforms
    assert :only_type in taxonomy.filters
    assert :without_nodes in taxonomy.filters
    assert :collapse_type in taxonomy.collapse
    assert View.verbs() == taxonomy
  end

  test "zoom is pipe friendly" do
    system = sample_system()

    zoomed = View.zoom(system, 1)

    assert Enum.sort(Map.keys(Choreo.nodes(zoomed))) == [:db, :policy, :redis, :router]
  end

  test "focus accepts depth as a friendlier radius alias" do
    system = sample_system()

    focused = View.focus(system, :router, depth: 1)

    assert Enum.sort(Map.keys(Choreo.nodes(focused))) == [:api, :db, :policy, :router]
  end

  test "between and path keep shortest paths" do
    system = sample_system()

    between = View.between(system, :client, :db)
    path = View.path(system, :client, :db)

    assert Enum.sort(Map.keys(Choreo.nodes(between))) == [:api, :client, :db, :router]
    assert Enum.sort(Map.keys(Choreo.nodes(path))) == [:api, :client, :db, :router]
  end

  test "only and without filters support nodes and types" do
    system = sample_system()

    only = View.only(system, type: [:service], nodes: [:db])
    without = View.without(system, type: [:cache], nodes: [:client])

    assert Enum.sort(Map.keys(Choreo.nodes(only))) == [:db, :policy, :router]
    refute Map.has_key?(Choreo.nodes(without), :redis)
    refute Map.has_key?(Choreo.nodes(without), :client)
  end

  test "specific type and node filters are pipe friendly" do
    system = sample_system()

    service_view = View.only_type(system, :service)
    no_policy = View.without_nodes(system, :policy)

    assert Enum.sort(Map.keys(Choreo.nodes(service_view))) == [:policy, :router]
    refute Map.has_key?(Choreo.nodes(no_policy), :policy)
  end

  test "collapse helpers aggregate nodes" do
    system = sample_system()

    collapsed_nodes = View.collapse_nodes(system, [:redis, :db], :state, label: "State")
    collapsed_type = View.collapse_type(system, :service, :services, label: "Services")

    assert Map.has_key?(Choreo.nodes(collapsed_nodes), :state)
    refute Map.has_key?(Choreo.nodes(collapsed_nodes), :redis)
    refute Map.has_key?(Choreo.nodes(collapsed_nodes), :db)

    assert Map.has_key?(Choreo.nodes(collapsed_type), :services)
    refute Map.has_key?(Choreo.nodes(collapsed_type), :router)
    refute Map.has_key?(Choreo.nodes(collapsed_type), :policy)
  end

  defp sample_system do
    infrastructure do
      client = user("API Client")
      api = gateway("API Gateway")
      router = service("Tenant Router")
      policy = service("Policy Engine")
      redis = cache("Redis", kind: :redis)
      db = database("Postgres", kind: :postgres)

      client ~> api
      api ~> redis |> on("checks quota")
      api ~> router |> on("routes")
      router ~> policy
      router ~> db |> on("reads")
    end
  end
end
