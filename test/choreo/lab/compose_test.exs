defmodule Choreo.Lab.ComposeTest do
  use ExUnit.Case, async: true

  alias Choreo.Lab.Compose

  doctest Choreo.Lab.Compose

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Compose.taxonomy()

    assert :cluster in taxonomy.structure
    assert :embed in taxonomy.structure
    assert :connect in taxonomy.links
    assert :trace in taxonomy.links
    assert :into in taxonomy.options
    assert :as in taxonomy.options
    assert Compose.verbs() == taxonomy
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

  test "embed defaults to sub_ prefix when neither as nor prefix is provided" do
    child = Choreo.new() |> Choreo.add_service(:worker)

    system =
      Choreo.new()
      |> Compose.cluster(:jobs)
      |> Compose.embed(child, into: :jobs)

    assert Map.has_key?(Choreo.nodes(system), :sub_worker)
  end

  test "connect creates normal visible relationships" do
    system =
      Choreo.new()
      |> Choreo.add_service(:api)
      |> Choreo.add_database(:db)
      |> Compose.connect(:api, :db, "reads")
      |> Compose.connect(:db, :api, label: "writes")

    assert length(Choreo.edges_with_meta(system)) == 2
  end

  test "trace creates semantic cross-model relationships" do
    system =
      Choreo.new()
      |> Choreo.add_service(:api)
      |> Choreo.add_service(:auth)
      |> Compose.trace(:api, :auth, :executes)
      |> Compose.trace(:auth, :api, type: :validates)

    assert length(Choreo.edges_with_meta(system)) == 2
  end
end
