defmodule Choreo.Requirement.AnalysisTest do
  use ExUnit.Case

  alias Choreo.Requirement
  alias Choreo.Requirement.Analysis

  doctest Analysis

  defp sample_model do
    Requirement.new("Auth v2")
    |> Requirement.add_requirement(:mfa,
      id: "REQ-001",
      text: "Users must authenticate with MFA",
      risk: :high
    )
    |> Requirement.add_requirement(:password,
      id: "REQ-002",
      text: "Password must be strong",
      risk: :medium
    )
    |> Requirement.add_requirement(:sso,
      id: "REQ-003",
      text: "SSO via OAuth",
      risk: :low
    )
    |> Requirement.add_requirement(:orphan,
      id: "REQ-004",
      text: "Orphan requirement",
      risk: :low
    )
    |> Requirement.add_component(:auth_service, label: "Auth Service")
    |> Requirement.add_component(:db, label: "User DB")
    |> Requirement.add_test(:mfa_test, label: "MFA test")
    |> Requirement.satisfies(:auth_service, :mfa)
    |> Requirement.satisfies(:auth_service, :password)
    |> Requirement.satisfies(:db, :password)
    |> Requirement.verifies(:mfa_test, :mfa)
    |> Requirement.depends(:sso, :mfa)
  end

  describe "orphan_requirements/1" do
    test "finds requirements with no relationships" do
      req = sample_model()
      assert Analysis.orphan_requirements(req) == [:orphan]
    end
  end

  describe "unsatisfied/1" do
    test "finds requirements with no satisfies edge" do
      req = sample_model()
      assert Analysis.unsatisfied(req) == [:orphan, :sso]
    end
  end

  describe "unverified/1" do
    test "finds requirements with no verifies edge" do
      req = sample_model()
      assert Analysis.unverified(req) == [:orphan, :password, :sso]
    end
  end

  describe "coverage/1" do
    test "returns coverage statistics" do
      req = sample_model()
      coverage = Analysis.coverage(req)

      assert coverage.total == 4
      assert Enum.sort(coverage.satisfied) == [:mfa, :password]
      assert Enum.sort(coverage.verified) == [:mfa]
      assert coverage.orphan == [:orphan]
      assert coverage.ratios.satisfied == 0.5
      assert coverage.ratios.verified == 0.25
      assert coverage.ratios.orphan == 0.25
    end
  end

  describe "traceability_matrix/1" do
    test "maps requirements to related nodes" do
      req = sample_model()
      matrix = Analysis.traceability_matrix(req)

      assert :auth_service in matrix[:mfa].components
      assert :mfa_test in matrix[:mfa].tests
      assert :auth_service in matrix[:password].components
      assert :db in matrix[:password].components
    end
  end

  describe "requirements_for/2" do
    test "returns requirements related to a component" do
      req = sample_model()
      assert Enum.sort(Analysis.requirements_for(req, :auth_service)) == [:mfa, :password]
    end
  end

  describe "components_for/2" do
    test "returns components related to a requirement" do
      req = sample_model()
      assert Enum.sort(Analysis.components_for(req, :password)) == [:auth_service, :db]
    end
  end

  describe "high_risk_gaps/1" do
    test "finds high-risk requirements that are not fully covered" do
      req = sample_model()
      # mfa is satisfied and verified, so no high-risk gaps
      assert Analysis.high_risk_gaps(req) == []
    end

    test "finds high-risk unsatisfied requirements" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:critical, id: "R1", text: "Critical", risk: :critical)

      assert Analysis.high_risk_gaps(req) == [:critical]
    end
  end

  describe "risk_propagation/1" do
    test "propagates risk from parent to child" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:parent, id: "P", text: "Parent", risk: :critical)
        |> Requirement.add_requirement(:child, id: "C", text: "Child", risk: :low)
        |> Requirement.refines(:child, :parent)

      propagated = Analysis.risk_propagation(req)
      assert propagated[:child] == :critical
      assert propagated[:parent] == :critical
    end
  end

  describe "unmitigated_risks/1" do
    test "finds high-risk requirements without lower-risk children" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:parent, id: "P", text: "Parent", risk: :high)
        |> Requirement.add_requirement(:child, id: "C", text: "Child", risk: :low)
        |> Requirement.refines(:child, :parent)

      assert Analysis.unmitigated_risks(req) == []
    end

    test "finds high-risk leaf requirements" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:leaf, id: "L", text: "Leaf", risk: :high)

      assert Analysis.unmitigated_risks(req) == [:leaf]
    end
  end

  describe "impact_of/2" do
    test "returns related nodes" do
      req = sample_model()
      assert Enum.sort(Analysis.impact_of(req, :auth_service)) == [:mfa, :password]
    end

    test "follows dependency direction" do
      req = sample_model()
      assert :sso in Analysis.impact_of(req, :mfa)
    end
  end

  describe "circular_dependencies/1" do
    test "detects cycles" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:a, id: "A", text: "A")
        |> Requirement.add_requirement(:b, id: "B", text: "B")
        |> Requirement.add_requirement(:c, id: "C", text: "C")
        |> Requirement.depends(:a, :b)
        |> Requirement.depends(:b, :c)
        |> Requirement.depends(:c, :a)

      cycles = Analysis.circular_dependencies(req)
      assert length(cycles) == 1
      cycle = List.first(cycles)
      assert length(cycle) == 3
    end

    test "returns empty when no cycles" do
      req = sample_model()
      assert Analysis.circular_dependencies(req) == []
    end
  end

  describe "validate/1" do
    test "reports missing requirement id and text" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:bad, id: "", text: "")

      errors = Analysis.validate(req)

      assert Enum.any?(errors, fn {sev, msg} ->
               sev == :error and msg =~ "missing a required :id"
             end)

      assert Enum.any?(errors, fn {sev, msg} ->
               sev == :error and msg =~ "missing required :text"
             end)
    end

    test "reports duplicate human requirement IDs" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:login, id: "REQ-001", text: "Login")
        |> Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")

      errors = Analysis.validate(req)

      assert Enum.any?(errors, fn {sev, msg} ->
               sev == :error and
                 msg =~ ~s(Requirement ID "REQ-001" is used by multiple requirement nodes) and
                 msg =~ ":login" and msg =~ ":mfa"
             end)
    end

    test "reports circular dependencies" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:a, id: "A", text: "A")
        |> Requirement.add_requirement(:b, id: "B", text: "B")
        |> Requirement.depends(:a, :b)
        |> Requirement.depends(:b, :a)

      warnings = Analysis.validate(req)

      assert Enum.any?(warnings, fn {sev, msg} ->
               sev == :warning and msg =~ "Circular dependency"
             end)
    end

    test "validate_messages/1 returns strings" do
      req =
        Requirement.new()
        |> Requirement.add_requirement(:bad, id: "", text: "")

      messages = Analysis.validate_messages(req)

      assert Enum.any?(messages, fn {sev, msg} ->
               sev == :error and msg =~ "missing a required :id"
             end)
    end
  end
end
