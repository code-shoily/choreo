defmodule Choreo.ThreatModelTest do
  use ExUnit.Case

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
      assert model.boundaries["boundary_internet"].label == "Internet"
    end

    test "preserves existing prefix" do
      model = ThreatModel.new() |> ThreatModel.add_trust_boundary("boundary_internal")
      assert Map.has_key?(model.boundaries, "boundary_internal")
    end
  end

  describe "element builders" do
    test "add_external_entity/3" do
      model = ThreatModel.new() |> ThreatModel.add_external_entity(:user, label: "User")
      assert :user in ThreatModel.elements(model)
      assert Yog.node(model.graph, :user).element_type == :external_entity
    end

    test "add_process/3 with privilege" do
      model = ThreatModel.new() |> ThreatModel.add_process(:api, label: "API", privilege: :admin)
      assert :api in ThreatModel.elements(model)
      assert Yog.node(model.graph, :api).element_type == :process
      assert Yog.node(model.graph, :api).privilege == :admin
    end

    test "add_data_store/3 with sensitivity" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_data_store(:db, label: "Postgres", sensitivity: :confidential)

      assert :db in ThreatModel.elements(model)
      assert Yog.node(model.graph, :db).element_type == :data_store
      assert Yog.node(model.graph, :db).sensitivity == :confidential
    end
  end

  describe "data_flow/4" do
    test "creates a flow edge" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api, label: "request")

      assert Yog.has_edge?(model.graph, :user, :api)
      assert model.edge_meta[{:user, :api}].label == "request"
      refute model.edge_meta[{:user, :api}].encrypted
    end

    test "stores encrypted flag" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api, encrypted: true)

      assert model.edge_meta[{:user, :api}].encrypted
    end
  end

  describe "boundary queries" do
    test "boundary_of/2 returns boundary name" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app")
        |> ThreatModel.add_process(:api, boundary: "app")

      assert ThreatModel.boundary_of(model, :api) == "boundary_app"
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
      assert String.contains?(dot, "boundary_internet")
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
