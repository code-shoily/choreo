defmodule Choreo.ThreatModel.AnalysisTest do
  use ExUnit.Case

  alias Choreo.ThreatModel
  alias Choreo.ThreatModel.Analysis

  def simple_model do
    ThreatModel.new()
    |> ThreatModel.add_trust_boundary("internet", level: 0)
    |> ThreatModel.add_trust_boundary("app", level: 2)
    |> ThreatModel.add_trust_boundary("db", level: 3)
    |> ThreatModel.add_external_entity(:user, label: "User", boundary: "internet")
    |> ThreatModel.add_process(:api, label: "API", boundary: "app")
    |> ThreatModel.add_data_store(:postgres,
      label: "Postgres",
      boundary: "db",
      sensitivity: :confidential
    )
    |> ThreatModel.data_flow(:user, :api, label: "Login")
    |> ThreatModel.data_flow(:api, :postgres, label: "Query")
  end

  def encrypted_model do
    ThreatModel.new()
    |> ThreatModel.add_trust_boundary("internet", level: 0)
    |> ThreatModel.add_trust_boundary("app", level: 2)
    |> ThreatModel.add_external_entity(:user, boundary: "internet")
    |> ThreatModel.add_process(:api, boundary: "app")
    |> ThreatModel.data_flow(:user, :api, encrypted: true)
  end

  describe "stride_threats/1" do
    test "generates threats for external entity" do
      threats = Analysis.stride_threats(simple_model())

      user_threats = Enum.filter(threats, &(&1.target == :user))
      assert Enum.any?(user_threats, &(&1.category == :spoofing))
      assert Enum.any?(user_threats, &(&1.category == :repudiation))
    end

    test "generates threats for process" do
      threats = Analysis.stride_threats(simple_model())

      api_threats = Enum.filter(threats, &(&1.target == :api))
      assert Enum.any?(api_threats, &(&1.category == :spoofing))
      assert Enum.any?(api_threats, &(&1.category == :tampering))
      assert Enum.any?(api_threats, &(&1.category == :information_disclosure))
    end

    test "generates threats for data store" do
      threats = Analysis.stride_threats(simple_model())

      db_threats = Enum.filter(threats, &(&1.target == :postgres))
      assert Enum.any?(db_threats, &(&1.category == :tampering))
      assert Enum.any?(db_threats, &(&1.category == :information_disclosure))
    end

    test "generates threats for data flows" do
      threats = Analysis.stride_threats(simple_model())

      flow_threats = Enum.filter(threats, fn t -> match?({_, _}, t.target) end)
      assert Enum.any?(flow_threats, &(&1.category == :tampering))
      assert Enum.any?(flow_threats, &(&1.category == :information_disclosure))
    end

    test "elevates severity for cross-boundary flows" do
      threats = Analysis.stride_threats(simple_model())

      cross_boundary =
        Enum.filter(threats, fn t ->
          match?({:user, :api}, t.target) and t.category == :tampering
        end)

      assert hd(cross_boundary).severity == :high
    end

    test "lowers severity for encrypted flows" do
      encrypted = encrypted_model()
      threats = Analysis.stride_threats(encrypted)

      flow_threats =
        Enum.filter(threats, fn t ->
          match?({:user, :api}, t.target)
        end)

      # Should be lowered from high because encrypted (medium or low)
      refute Enum.any?(flow_threats, &(&1.severity == :high))
      refute Enum.any?(flow_threats, &(&1.severity == :critical))
    end

    test "assigns unique IDs" do
      threats = Analysis.stride_threats(simple_model())
      ids = Enum.map(threats, & &1.id)
      assert length(ids) == length(Enum.uniq(ids))
      assert Enum.all?(ids, &String.starts_with?(&1, "T"))
    end
  end

  describe "cross_boundary_flows/1" do
    test "finds flows crossing boundaries" do
      flows = Analysis.cross_boundary_flows(simple_model())
      assert length(flows) == 2

      assert Enum.any?(flows, fn {from, to, _, _} -> from == :user and to == :api end)
      assert Enum.any?(flows, fn {from, to, _, _} -> from == :api and to == :postgres end)
    end
  end

  describe "exposed_data_stores/1" do
    test "finds stores reachable from external entities" do
      model = simple_model()
      assert :postgres in Analysis.exposed_data_stores(model)
    end

    test "ignores isolated stores" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_data_store(:secret)

      assert Analysis.exposed_data_stores(model) == []
    end
  end

  describe "high_risk_processes/1" do
    test "finds processes accessing sensitive data" do
      model = simple_model()
      assert :api in Analysis.high_risk_processes(model)
    end

    test "ignores processes without sensitive access" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.add_data_store(:logs, boundary: "app", sensitivity: :public)
        |> ThreatModel.data_flow(:api, :logs)

      refute :api in Analysis.high_risk_processes(model)
    end
  end

  describe "unencrypted_boundary_flows/1" do
    test "flags unencrypted cross-boundary flows" do
      model = simple_model()
      flows = Analysis.unencrypted_boundary_flows(model)
      assert {:user, :api} in flows
      assert {:api, :postgres} in flows
    end

    test "ignores encrypted flows" do
      model = encrypted_model()
      assert Analysis.unencrypted_boundary_flows(model) == []
    end
  end

  describe "validate/1" do
    test "returns empty for well-formed model" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app")
        |> ThreatModel.add_process(:api, boundary: "app", privilege: :user)
        |> ThreatModel.add_data_store(:db, boundary: "app", sensitivity: :internal)
        |> ThreatModel.data_flow(:api, :db, encrypted: true)

      assert Analysis.validate(model) == []
    end

    test "flags unencrypted boundary flows" do
      issues = Analysis.validate(simple_model())
      assert Enum.any?(issues, fn {sev, _} -> sev == :error end)
    end

    test "flags missing boundaries" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_process(:api)

      issues = Analysis.validate(model)
      assert {:warning, "Elements not assigned to a trust boundary: [:api]"} in issues
    end

    test "flags unclassified processes" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app")
        |> ThreatModel.add_process(:api, boundary: "app")

      issues = Analysis.validate(model)
      assert {:warning, "Processes without privilege level: [:api]"} in issues
    end

    test "flags unclassified data stores" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app")
        |> ThreatModel.add_data_store(:db, boundary: "app")

      issues = Analysis.validate(model)
      assert {:warning, "Data stores without sensitivity: [:db]"} in issues
    end
  end

  describe "attack_paths/1" do
    test "finds paths from external entities to data stores" do
      paths = Analysis.attack_paths(simple_model())

      assert paths != []
      assert [:user, :api, :postgres] in paths
    end

    test "returns empty when no data stores are reachable" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api)

      assert Analysis.attack_paths(model) == []
    end

    test "returns empty when no external entities exist" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:api, :db)

      assert Analysis.attack_paths(model) == []
    end
  end

  describe "threat_summary/1" do
    test "returns summary with by_category, by_severity, and total" do
      summary = Analysis.threat_summary(simple_model())

      assert is_map(summary.by_category)
      assert is_map(summary.by_severity)
      assert is_integer(summary.total)
      assert summary.total > 0
    end

    test "total matches actual threat count" do
      model = simple_model()
      threats = Analysis.stride_threats(model)
      summary = Analysis.threat_summary(model)

      assert summary.total == length(threats)
    end

    test "by_category sums match total" do
      summary = Analysis.threat_summary(simple_model())

      category_total =
        summary.by_category
        |> Enum.flat_map(fn {_cat, sevs} -> Map.values(sevs) end)
        |> Enum.sum()

      assert category_total == summary.total
    end
  end

  describe "stride_threats/1 — data store EoP" do
    test "generates elevation_of_privilege for data stores" do
      threats = Analysis.stride_threats(simple_model())

      db_threats =
        threats
        |> Enum.filter(&(&1.target == :postgres))
        |> Enum.map(& &1.category)

      assert :elevation_of_privilege in db_threats
    end

    test "EoP severity scales with sensitivity" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app", level: 3)
        |> ThreatModel.add_data_store(:secret, boundary: "app", sensitivity: :restricted)

      threats = Analysis.stride_threats(model)

      eop =
        threats
        |> Enum.find(&(&1.target == :secret and &1.category == :elevation_of_privilege))

      assert eop.severity == :critical
    end
  end
end
