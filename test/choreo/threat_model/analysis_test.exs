defmodule Choreo.ThreatModel.AnalysisTest do
  use ExUnit.Case

  doctest Choreo.ThreatModel.Analysis

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

  describe "stride_threats/2" do
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

    test "downgrades STRIDE threat severity for unprivileged processes" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_process(:admin_api, boundary: "app", privilege: :admin)
        |> ThreatModel.add_process(:public_api, boundary: "app", privilege: :none)

      threats = Analysis.stride_threats(model)

      admin_spoofing = Enum.find(threats, &(&1.target == :admin_api and &1.category == :spoofing))
      none_spoofing = Enum.find(threats, &(&1.target == :public_api and &1.category == :spoofing))

      # :none privilege should lower the severity compared to :admin
      assert admin_spoofing.severity == :medium
      assert none_spoofing.severity == :low
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

    test "preserves custom rule IDs" do
      defmodule IdPreservingRule do
        @behaviour Analysis.Rule
        @impl true
        def threats_for_element(_, id, _) do
          [
            %{
              id: "CUSTOM-#{id}",
              category: :custom,
              target: id,
              description: "x",
              severity: :low,
              mitigation: "y"
            }
          ]
        end

        @impl true
        def threats_for_flow(_, from, to, _) do
          [
            %{
              id: "FLOW-#{from}-#{to}",
              category: :custom,
              target: {from, to},
              description: "x",
              severity: :low,
              mitigation: "y"
            }
          ]
        end
      end

      threats = Analysis.stride_threats(simple_model(), rules: [IdPreservingRule])
      custom = Enum.filter(threats, &(&1.category == :custom))

      assert Enum.any?(custom, &(&1.id == "CUSTOM-user"))
      assert Enum.any?(custom, &(&1.id == "FLOW-user-api"))
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

    test "respects max_paths option" do
      model = simple_model()
      all = Analysis.attack_paths(model)
      capped = Analysis.attack_paths(model, max_paths: 1)

      assert length(capped) == 1
      assert hd(capped) in all
    end
  end

  describe "threat_summary/1" do
    test "returns summary with by_category, by_severity, and total" do
      summary = Analysis.threat_summary(simple_model())

      assert %{elevation_of_privilege: _} = summary.by_category
      assert %{high: _} = summary.by_severity
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

  describe "risk_score/2" do
    test "calculates a numeric risk score and rating" do
      model = simple_model()
      %{score: score, rating: rating} = Analysis.risk_score(model)

      assert is_number(score)
      assert score > 0
      assert rating in [:none, :low, :medium, :high, :critical]
    end

    test "respects custom weights" do
      model = simple_model()
      result = Analysis.risk_score(model, weights: [low: 0, medium: 0, high: 0, critical: 0])
      assert result.score == 0
      assert result.rating == :none
    end
  end

  describe "stride_threats/2 — custom rules" do
    defmodule CustomRule do
      @behaviour Analysis.Rule

      @impl true
      def threats_for_element(_model, id, _data) do
        [
          %{
            id: "CUSTOM-#{id}",
            category: :custom_threat,
            target: id,
            description: "Custom threat for #{id}",
            severity: :medium,
            mitigation: "Review custom policy"
          }
        ]
      end

      @impl true
      def threats_for_flow(_model, from, to, _meta) do
        [
          %{
            id: "CUSTOM-FLOW-#{from}-#{to}",
            category: :custom_flow_threat,
            target: {from, to},
            description: "Custom flow threat",
            severity: :low,
            mitigation: "Inspect pipeline"
          }
        ]
      end
    end

    test "includes custom element threats via :rules" do
      threats = Analysis.stride_threats(simple_model(), rules: [CustomRule])
      custom = Enum.filter(threats, &(&1.category == :custom_threat))

      assert length(custom) == 3
      assert Enum.any?(custom, &(&1.target == :user))
      assert Enum.any?(custom, &(&1.target == :api))
      assert Enum.any?(custom, &(&1.target == :postgres))
    end

    test "includes custom flow threats via :rules" do
      threats = Analysis.stride_threats(simple_model(), rules: [CustomRule])
      custom = Enum.filter(threats, &(&1.category == :custom_flow_threat))

      assert length(custom) == 2
      assert Enum.any?(custom, &(&1.target == {:user, :api}))
      assert Enum.any?(custom, &(&1.target == {:api, :postgres}))
    end

    test "works without custom rules" do
      threats = Analysis.stride_threats(simple_model())
      refute Enum.any?(threats, &(&1.category == :custom_threat))
    end

    test "ignores rules missing optional callbacks" do
      defmodule PartialRule do
        @behaviour Analysis.Rule
        @impl true
        def threats_for_element(_, _, _), do: []
        # threats_for_flow is intentionally omitted
      end

      # Should not crash even though PartialRule lacks threats_for_flow
      threats = Analysis.stride_threats(simple_model(), rules: [PartialRule])
      assert [_ | _] = threats
    end

    test "passes flow metadata to custom rules" do
      defmodule MetaAwareRule do
        @behaviour Analysis.Rule
        @impl true
        def threats_for_element(_, _, _), do: []
        @impl true
        def threats_for_flow(_, from, to, meta) do
          if meta[:encrypted] do
            [
              %{
                id: "SAFE-#{from}-#{to}",
                category: :custom,
                target: {from, to},
                description: "x",
                severity: :low,
                mitigation: "y"
              }
            ]
          else
            [
              %{
                id: "UNSAFE-#{from}-#{to}",
                category: :custom,
                target: {from, to},
                description: "x",
                severity: :high,
                mitigation: "y"
              }
            ]
          end
        end
      end

      model = encrypted_model()
      threats = Analysis.stride_threats(model, rules: [MetaAwareRule])

      assert Enum.any?(threats, &(&1.id == "SAFE-user-api"))
    end
  end

  describe "stride_threats/2 — data store EoP" do
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

  describe "entry_points/1 and exit_points/1" do
    test "identifies ingress entry points" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet", level: 0)
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_external_entity(:user, boundary: "internet")
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.data_flow(:user, :api,
          label: "Login",
          authenticated: true,
          encrypted: true
        )

      [entry] = Analysis.entry_points(model)
      assert entry.source == :user
      assert entry.target == :api
      assert entry.from_boundary == "internet"
      assert entry.to_boundary == "app"
      assert entry.authenticated == true
      assert entry.encrypted == true
      assert entry.label == "Login"
    end

    test "identifies egress exit points" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet", level: 0)
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_external_entity(:webhook, boundary: "internet")
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.data_flow(:api, :webhook, label: "Notify", encrypted: true)

      [exit_point] = Analysis.exit_points(model)
      assert exit_point.source == :api
      assert exit_point.target == :webhook
      assert exit_point.from_boundary == "app"
      assert exit_point.to_boundary == "internet"
    end
  end

  describe "blast_radius/2" do
    test "calculates downstream impact and risk level correctly" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_trust_boundary("db", level: 3)
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.add_process(:worker, boundary: "app")
        |> ThreatModel.add_data_store(:postgres, boundary: "db", sensitivity: :restricted)
        |> ThreatModel.data_flow(:api, :worker)
        |> ThreatModel.data_flow(:worker, :postgres)

      radius = Analysis.blast_radius(model, :api)
      assert :worker in radius.reachable_nodes
      assert :postgres in radius.reachable_nodes
      assert radius.affected_stores == [:postgres]
      assert "db" in radius.affected_boundaries
      assert radius.max_sensitivity == :restricted
      assert radius.risk_level == :critical
    end

    test "returns empty reachable nodes and :none risk level for leaf nodes" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db, sensitivity: :public)
        |> ThreatModel.data_flow(:api, :db)

      radius = Analysis.blast_radius(model, :db)
      assert radius.reachable_nodes == []
      assert radius.affected_stores == []
      assert radius.risk_level == :none
    end
  end

  describe "highlight_attack_paths/2" do
    test "sets highlighted_nodes and highlighted_edges on the model" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:attacker)
        |> ThreatModel.add_process(:proxy)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:attacker, :proxy)
        |> ThreatModel.data_flow(:proxy, :db)

      highlighted = Analysis.highlight_attack_paths(model)
      assert :attacker in highlighted.highlighted_nodes
      assert :proxy in highlighted.highlighted_nodes
      assert :db in highlighted.highlighted_nodes
      assert {:attacker, :proxy} in highlighted.highlighted_edges
      assert {:proxy, :db} in highlighted.highlighted_edges
    end
  end

  describe "to_markdown/2" do
    test "renders markdown table and summary header" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app")
        |> ThreatModel.add_process(:api, boundary: "app", privilege: :user)

      md = Analysis.to_markdown(model)
      assert String.contains?(md, "### Threat Model Summary")
      assert String.contains?(md, "| ID | Category | Target |")
      assert String.contains?(md, "`api`")
    end

    test "respects summary: false option" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_process(:api)

      md = Analysis.to_markdown(model, summary: false)
      refute String.contains?(md, "### Threat Model Summary")
      assert String.contains?(md, "| ID | Category | Target |")
    end
  end

  describe "mitigations and unmitigated_threats/2" do
    test "marks threats mitigated when corresponding controls are present" do
      unmitigated_model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.add_data_store(:db, boundary: "app")
        |> ThreatModel.data_flow(:api, :db)

      all_threats = Analysis.stride_threats(unmitigated_model)
      unmitigated_count = length(Analysis.unmitigated_threats(unmitigated_model))
      assert unmitigated_count == length(all_threats)

      mitigated_model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_process(:api,
          boundary: "app",
          controls: [:auth, :input_validation, :rate_limiting]
        )
        |> ThreatModel.add_data_store(:db, boundary: "app", controls: [:encryption_at_rest])
        |> ThreatModel.data_flow(:api, :db, encrypted: true)

      remaining = Analysis.unmitigated_threats(mitigated_model)
      assert length(remaining) < length(Analysis.stride_threats(mitigated_model))
    end
  end

  describe "threats_for/3" do
    test "filters threats targeting a specific element" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:api, :db)

      api_only = Analysis.threats_for(model, :api, include_flows: false)
      assert Enum.all?(api_only, &(&1.target == :api))

      api_with_flows = Analysis.threats_for(model, :api, include_flows: true)
      assert Enum.any?(api_with_flows, &match?({:api, :db}, &1.target))
    end
  end

  describe "residual_risk_score/2" do
    test "scores only unmitigated threats" do
      mitigated_model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_process(:api,
          boundary: "app",
          controls: [:auth, :input_validation, :rate_limiting]
        )
        |> ThreatModel.add_data_store(:db,
          boundary: "app",
          sensitivity: :confidential,
          controls: [:encryption_at_rest, :rbac]
        )
        |> ThreatModel.data_flow(:api, :db, encrypted: true, controls: [:integrity])

      inherent = Analysis.risk_score(mitigated_model)
      residual = Analysis.residual_risk_score(mitigated_model)

      assert residual.score < inherent.score
      assert residual == Analysis.risk_score(mitigated_model, only_unmitigated: true)
      assert ThreatModel.residual_risk_score(mitigated_model) == residual
    end
  end

  describe "control_gaps/1" do
    test "reports missing controls on risky flows and elements" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet", level: 0)
        |> ThreatModel.add_trust_boundary("app", level: 1)
        |> ThreatModel.add_trust_boundary("data", level: 3)
        |> ThreatModel.add_external_entity(:user, boundary: "internet")
        |> ThreatModel.add_process(:api, boundary: "app", privilege: :admin)
        |> ThreatModel.add_data_store(:db, boundary: "data", sensitivity: :restricted)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :db, data: :customer_record, sensitivity: :restricted)

      gaps = Analysis.control_gaps(model)

      assert Enum.any?(gaps, &(&1.target == {:user, :api} and :authentication in &1.missing))
      assert Enum.any?(gaps, &(&1.target == {:api, :db} and :encryption_in_transit in &1.missing))
      assert Enum.any?(gaps, &(&1.target == :db and :encryption_at_rest in &1.missing))
      assert Enum.any?(gaps, &(&1.target == :api and :least_privilege in &1.missing))
      assert ThreatModel.control_gaps(model) == gaps
    end
  end

  describe "exfiltration_paths/2" do
    test "finds sensitive data paths to external entities" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_process(:exporter)
        |> ThreatModel.add_data_store(:db, sensitivity: :restricted)
        |> ThreatModel.add_external_entity(:partner)
        |> ThreatModel.data_flow(:db, :api)
        |> ThreatModel.data_flow(:api, :exporter)
        |> ThreatModel.data_flow(:exporter, :partner)

      assert [:db, :api, :exporter, :partner] in Analysis.exfiltration_paths(model)
      assert Analysis.exfiltration_paths(model, max_paths: 1) |> length() == 1
      assert ThreatModel.exfiltration_paths(model) == Analysis.exfiltration_paths(model)
    end

    test "ignores public stores by default" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_data_store(:logs, sensitivity: :public)
        |> ThreatModel.add_external_entity(:partner)
        |> ThreatModel.data_flow(:logs, :partner)

      assert Analysis.exfiltration_paths(model) == []
      assert Analysis.exfiltration_paths(model, sensitivity: :public) == [[:logs, :partner]]
    end
  end

  describe "boundary_matrix/1" do
    test "summarises flows between trust boundaries" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet", level: 0)
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_trust_boundary("data", level: 3)
        |> ThreatModel.add_external_entity(:user, boundary: "internet")
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.add_data_store(:db, boundary: "data", sensitivity: :confidential)
        |> ThreatModel.data_flow(:user, :api, encrypted: true, authenticated: true)
        |> ThreatModel.data_flow(:api, :db, sensitivity: :confidential)

      matrix = Analysis.boundary_matrix(model)

      assert matrix[{"internet", "app"}].count == 1
      assert matrix[{"internet", "app"}].encrypted == 1
      assert matrix[{"internet", "app"}].authenticated == 1
      assert matrix[{"app", "data"}].unencrypted == 1
      assert matrix[{"app", "data"}].max_sensitivity == :confidential
      assert ThreatModel.boundary_matrix(model) == matrix
    end
  end

  describe "prioritized_findings/2" do
    test "combines and sorts review findings" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet", level: 0)
        |> ThreatModel.add_trust_boundary("app", level: 1)
        |> ThreatModel.add_trust_boundary("data", level: 3)
        |> ThreatModel.add_external_entity(:user, boundary: "internet")
        |> ThreatModel.add_process(:api, boundary: "app", privilege: :admin)
        |> ThreatModel.add_data_store(:db, boundary: "data", sensitivity: :restricted)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :db, sensitivity: :restricted)
        |> ThreatModel.data_flow(:db, :user, sensitivity: :restricted)

      findings = Analysis.prioritized_findings(model)

      assert [%{id: "F1"} | _] = findings
      assert Enum.any?(findings, &(&1.kind == :exposed_data_store and &1.target == :db))
      assert Enum.any?(findings, &(&1.kind == :exfiltration_path and &1.target == :db))
      assert Enum.any?(findings, &(&1.kind == :control_gap))
      assert Enum.all?(findings, &Map.has_key?(&1, :recommendation))
      assert length(Analysis.prioritized_findings(model, max_findings: 2)) == 2

      assert ThreatModel.prioritized_findings(model, max_findings: 2) ==
               Analysis.prioritized_findings(model, max_findings: 2)
    end
  end

  describe "extended validate/2 checks" do
    test "flags direct data flow between external entity and data store" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet")
        |> ThreatModel.add_trust_boundary("data")
        |> ThreatModel.add_external_entity(:user, boundary: "internet")
        |> ThreatModel.add_data_store(:db, boundary: "data", sensitivity: :confidential)
        |> ThreatModel.data_flow(:user, :db, encrypted: true)

      issues = Analysis.validate(model)

      assert Enum.any?(issues, fn {sev, msg} ->
               sev == :error and
                 String.contains?(msg, "Direct data flow between external entity and data store")
             end)
    end

    test "flags sensitive data stores placed in low-trust boundaries" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("dmz", level: 1)
        |> ThreatModel.add_process(:proxy, boundary: "dmz", privilege: :user)
        |> ThreatModel.add_data_store(:db, boundary: "dmz", sensitivity: :restricted)
        |> ThreatModel.data_flow(:proxy, :db, encrypted: true)

      issues = Analysis.validate(model)

      assert Enum.any?(issues, fn {sev, msg} ->
               sev == :warning and String.contains?(msg, "sits in low-trust boundary")
             end)
    end

    test "flags boundaries missing :level when require_levels: true is set" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app")
        |> ThreatModel.add_process(:api, boundary: "app", privilege: :user)
        |> ThreatModel.add_data_store(:db, boundary: "app", sensitivity: :internal)
        |> ThreatModel.data_flow(:api, :db, encrypted: true)

      refute Enum.any?(Analysis.validate(model), fn {_sev, msg} ->
               String.contains?(msg, "without a `:level`")
             end)

      issues = Analysis.validate(model, require_levels: true)

      assert Enum.any?(issues, fn {sev, msg} ->
               sev == :warning and String.contains?(msg, "without a `:level`")
             end)
    end
  end
end
