defmodule Choreo.Lab.ComposeTest do
  use ExUnit.Case, async: true

  alias Choreo.Lab.Compose

  doctest Choreo.Lab.Compose

  test "verbs returns the Livebook discovery vocabulary" do
    verbs = Compose.verbs()

    assert :cluster in verbs.structure
    assert :embed in verbs.structure
    assert :connect in verbs.links
    assert :trace in verbs.links
    assert :into in verbs.options
    assert :as in verbs.options
  end

  test "cluster adds a visual grouping" do
    system = Choreo.new() |> Compose.cluster(:auth, label: "Auth")

    assert system.clusters["cluster_auth"].label == "Auth"
  end

  test "embed supports friendly as prefix" do
    child = Choreo.new() |> Choreo.add_service(:api)

    system =
      Choreo.new()
      |> Compose.cluster(:system)
      |> Compose.embed(child, into: :system, as: :child)

    assert Map.has_key?(Choreo.nodes(system), :child_api)
    assert Choreo.nodes(system)[:child_api].cluster == "cluster_system"
  end

  test "explicit prefix wins over as" do
    child = Choreo.new() |> Choreo.add_service(:api)

    system =
      Choreo.new()
      |> Compose.cluster(:system)
      |> Compose.embed(child, into: :system, as: :child, prefix: "explicit_")

    assert Map.has_key?(Choreo.nodes(system), :explicit_api)
    refute Map.has_key?(Choreo.nodes(system), :child_api)
  end

  test "connect creates normal visible relationships" do
    system =
      Choreo.new()
      |> Choreo.add_service(:api)
      |> Choreo.add_database(:db)
      |> Compose.connect(:api, :db, "reads")

    assert [{:api, :db, _weight, meta}] = Choreo.edges_with_meta(system)
    assert meta.label == "reads"
    refute meta[:edge_type] == :trace
  end

  test "trace creates semantic cross-model relationships" do
    system =
      Choreo.new()
      |> Choreo.add_service(:api)
      |> Choreo.add_service(:auth)
      |> Compose.trace(:api, :auth, :executes)

    assert [{:api, :auth, _weight, meta}] = Choreo.edges_with_meta(system)
    assert meta.edge_type == :trace
    assert meta.type == :executes
    assert meta.label == "executes"
  end
end
