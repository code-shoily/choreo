defmodule Choreo.ThreatModelTest do
  use ExUnit.Case

  doctest Choreo.ThreatModel
  doctest Choreo.ThreatModel.Render.DOT
  doctest Choreo.ThreatModel.Render.PlantUML

  alias Choreo.ThreatModel

  describe "new/0" do
    test "creates an empty model" do
      model = ThreatModel.new()
      assert ThreatModel.elements(model) == []
      assert ThreatModel.flows(model) == []
    end
  end

  describe "add_trust_boundary/3" do
    test "adds a boundary with prefix" do
      model = ThreatModel.new() |> ThreatModel.add_trust_boundary("internet", label: "Internet")
      assert model.clusters["cluster_internet"].label == "Internet"
    end

    test "preserves existing cluster_ prefix" do
      model = ThreatModel.new() |> ThreatModel.add_trust_boundary("cluster_internal")
      assert Map.has_key?(model.clusters, "cluster_internal")
    end
  end

  describe "element builders" do
    test "add_external_entity/3" do
      model = ThreatModel.new() |> ThreatModel.add_external_entity(:user, label: "User")
      assert :user in ThreatModel.elements(model)
      assert Map.get(model.graph.nodes, :user).element_type == :external_entity
    end

    test "add_process/3 with privilege" do
      model = ThreatModel.new() |> ThreatModel.add_process(:api, label: "API", privilege: :admin)
      assert :api in ThreatModel.elements(model)
      assert Map.get(model.graph.nodes, :api).element_type == :process
      assert Map.get(model.graph.nodes, :api).privilege == :admin
    end

    test "add_data_store/3 with sensitivity" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_data_store(:db, label: "Postgres", sensitivity: :confidential)

      assert :db in ThreatModel.elements(model)
      assert Map.get(model.graph.nodes, :db).element_type == :data_store
      assert Map.get(model.graph.nodes, :db).sensitivity == :confidential
    end

    test "raises on arbitrary options in process" do
      assert_raise NimbleOptions.ValidationError, fn ->
        ThreatModel.new() |> ThreatModel.add_process(:api, compliance: :gdpr, owner: "team-a")
      end
    end

    test "raises on arbitrary options in data store" do
      assert_raise NimbleOptions.ValidationError, fn ->
        ThreatModel.new() |> ThreatModel.add_data_store(:db, retention: "90d")
      end
    end

    test "raises on arbitrary options in external entity" do
      assert_raise NimbleOptions.ValidationError, fn ->
        ThreatModel.new() |> ThreatModel.add_external_entity(:user, region: "eu")
      end
    end
  end

  describe "data_flow/4" do
    test "creates a flow edge" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api, label: "request")

      assert [{:user, :api, _, meta}] = ThreatModel.edges_with_meta(model)
      assert meta.label == "request"
      refute meta.encrypted
    end

    test "stores encrypted flag" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api, encrypted: true)

      assert [{:user, :api, _, meta}] = ThreatModel.edges_with_meta(model)
      assert meta.encrypted
    end

    test "allows parallel connections" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api, label: "request1")
        |> ThreatModel.data_flow(:user, :api, label: "request2")

      assert length(ThreatModel.flows(model)) == 2
    end
  end

  describe "boundary queries" do
    test "boundary_of/2 returns boundary name" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app")
        |> ThreatModel.add_process(:api, boundary: "app")

      assert ThreatModel.boundary_of(model, :api) == "cluster_app"
    end

    test "trust_level/2 returns numeric level" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("dmz", level: 1)
        |> ThreatModel.add_process(:api, boundary: "dmz")

      assert ThreatModel.trust_level(model, :api) == 1
    end

    test "crosses_boundary?/3 detects boundary crossing" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet", level: 0)
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_external_entity(:user, boundary: "internet")
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.add_process(:worker, boundary: "app")
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :worker)

      assert ThreatModel.crosses_boundary?(model, :user, :api)
      refute ThreatModel.crosses_boundary?(model, :api, :worker)
    end
  end

  describe "to_dot/2" do
    test "renders a non-empty DOT string" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet", label: "Internet")
        |> ThreatModel.add_external_entity(:user, label: "User", boundary: "internet")
        |> ThreatModel.add_process(:api, label: "API")
        |> ThreatModel.data_flow(:user, :api, label: "HTTPS")

      dot = ThreatModel.to_dot(model)
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "User")
      assert String.contains?(dot, "API")
      assert String.contains?(dot, "cluster_internet")
    end

    test "renders unencrypted cross-boundary flow in red" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet")
        |> ThreatModel.add_trust_boundary("app")
        |> ThreatModel.add_external_entity(:user, boundary: "internet")
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.data_flow(:user, :api)

      dot = ThreatModel.to_dot(model)
      assert String.contains?(dot, "#ef4444")
    end

    test "renders with dark theme" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api)

      dot = ThreatModel.to_dot(model, theme: :dark)
      assert String.contains?(dot, "digraph")
    end
  end
end
