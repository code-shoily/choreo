defmodule Choreo.Workflow.AnalysisTest do
  use ExUnit.Case

  alias Choreo.Workflow
  alias Choreo.Workflow.Analysis

  def order_workflow do
    Workflow.new()
    |> Workflow.add_start(:order_received)
    |> Workflow.add_task(:charge_card, timeout_ms: 5000)
    |> Workflow.add_task(:reserve_inventory, timeout_ms: 3000)
    |> Workflow.add_decision(:sufficient_stock)
    |> Workflow.add_task(:pack_items, timeout_ms: 10_000)
    |> Workflow.add_task(:ship_order, timeout_ms: 5000)
    |> Workflow.add_compensation(:refund_payment, for: :charge_card)
    |> Workflow.add_end(:done)
    |> Workflow.connect(:order_received, :charge_card)
    |> Workflow.connect(:charge_card, :reserve_inventory)
    |> Workflow.connect(:reserve_inventory, :sufficient_stock)
    |> Workflow.connect(:sufficient_stock, :pack_items, condition: "yes")
    |> Workflow.connect(:sufficient_stock, :refund_payment,
      condition: "no",
      edge_type: :compensation
    )
    |> Workflow.connect(:pack_items, :ship_order)
    |> Workflow.connect(:ship_order, :done)
    |> Workflow.connect(:refund_payment, :done)
  end

  def parallel_workflow do
    Workflow.new()
    |> Workflow.add_start(:start)
    |> Workflow.add_fork(:split)
    |> Workflow.add_task(:a, timeout_ms: 1000)
    |> Workflow.add_task(:b, timeout_ms: 2000)
    |> Workflow.add_task(:c, timeout_ms: 1500)
    |> Workflow.add_join(:merge)
    |> Workflow.add_end(:end)
    |> Workflow.connect(:start, :split)
    |> Workflow.connect(:split, :a)
    |> Workflow.connect(:split, :b)
    |> Workflow.connect(:split, :c)
    |> Workflow.connect(:a, :merge)
    |> Workflow.connect(:b, :merge)
    |> Workflow.connect(:c, :merge)
    |> Workflow.connect(:merge, :end)
  end

  describe "reachable_tasks/1" do
    test "returns all nodes reachable from starts" do
      reachable = Analysis.reachable_tasks(order_workflow())
      assert :charge_card in reachable
      assert :ship_order in reachable
      assert :done in reachable
    end
  end

  describe "orphan_tasks/1" do
    test "returns nodes not reachable from any start" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)
        |> Workflow.add_task(:orphan)
        |> Workflow.connect(:a, :b)

      assert Analysis.orphan_tasks(workflow) == [:orphan]
    end
  end

  describe "dead_ends/1" do
    test "returns nodes that cannot reach an end" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)
        |> Workflow.add_task(:dead)
        |> Workflow.add_end(:finish)
        |> Workflow.connect(:a, :b)
        |> Workflow.connect(:b, :finish)

      assert Analysis.dead_ends(workflow) == [:dead]
    end
  end

  describe "critical_path/1" do
    test "finds the longest latency path" do
      {:ok, path, total} = Analysis.critical_path(order_workflow())
      assert :order_received in path
      assert :done in path
      assert total == 23_002
    end

    test "returns :error for cyclic workflow" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)
        |> Workflow.connect(:a, :b)
        |> Workflow.connect(:b, :a)

      assert Analysis.critical_path(workflow) == :error
    end
  end

  describe "parallelizable_tasks/1" do
    test "groups tasks by topological level" do
      groups = Analysis.parallelizable_tasks(parallel_workflow())
      # Level 0: start; Level 1: split; Level 2: a, b, c; Level 3: merge; Level 4: end
      assert length(groups) == 5

      assert [:a, :b, :c] in groups or
               Enum.sort(hd(Enum.filter(groups, fn g -> length(g) == 3 end))) == [:a, :b, :c]
    end
  end

  describe "failure_scenarios/1" do
    test "returns tasks with compensation edges" do
      scenarios = Analysis.failure_scenarios(order_workflow())
      assert :sufficient_stock in scenarios
    end
  end

  describe "missing_compensations/1" do
    test "returns tasks with retry but no compensation" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:risky, retry: 3)
        |> Workflow.add_task(:safe, retry: 2)
        |> Workflow.add_compensation(:rollback, for: :safe)
        |> Workflow.add_end(:end)
        |> Workflow.connect(:a, :risky)
        |> Workflow.connect(:risky, :safe)
        |> Workflow.connect(:safe, :end)
        |> Workflow.connect(:safe, :rollback, edge_type: :compensation)

      assert Analysis.missing_compensations(workflow) == [:risky]
    end
  end

  describe "bottlenecks/1" do
    test "returns high-latency tasks" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:fast, timeout_ms: 100)
        |> Workflow.add_task(:slow, timeout_ms: 20_000)

      assert Analysis.bottlenecks(workflow, latency_threshold: 10_000) == [:slow]
    end

    test "returns high-retry tasks" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:stable, retry: 0)
        |> Workflow.add_task(:flaky, retry: 5)

      assert Analysis.bottlenecks(workflow, retry_threshold: 3) == [:flaky]
    end
  end

  describe "simulate/1" do
    test "returns cumulative latency per node" do
      results = Analysis.simulate(order_workflow())
      assert results[:charge_card].task_latency == 5000
      assert results[:pack_items].task_latency == 10_000
    end
  end

  describe "validate/1" do
    test "returns empty for valid workflow" do
      assert Analysis.validate(order_workflow()) == []
    end

    test "flags missing start" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:a)
        |> Workflow.add_end(:b)
        |> Workflow.connect(:a, :b)

      issues = Analysis.validate(workflow)
      assert {:error, "No start nodes"} in issues
    end

    test "flags missing end" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)
        |> Workflow.connect(:a, :b)

      issues = Analysis.validate(workflow)
      assert {:error, "No end nodes"} in issues
    end

    test "flags cycles" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)
        |> Workflow.add_end(:c)
        |> Workflow.connect(:a, :b)
        |> Workflow.connect(:b, :a)

      issues = Analysis.validate(workflow)
      assert {:error, "Cycle detected in workflow"} in issues
    end

    test "flags orphan tasks" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)
        |> Workflow.add_task(:orphan)
        |> Workflow.add_end(:c)
        |> Workflow.connect(:a, :b)
        |> Workflow.connect(:b, :c)

      issues = Analysis.validate(workflow)
      assert {:warning, "Orphan tasks: [:orphan]"} in issues
    end

    test "flags dead-end tasks" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)
        |> Workflow.add_task(:dead)
        |> Workflow.add_end(:c)
        |> Workflow.connect(:a, :b)
        |> Workflow.connect(:b, :c)

      issues = Analysis.validate(workflow)
      assert {:warning, "Dead-end tasks: [:dead]"} in issues
    end

    test "flags missing compensations" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:risky, retry: 3)
        |> Workflow.add_end(:b)
        |> Workflow.connect(:a, :risky)
        |> Workflow.connect(:risky, :b)

      issues = Analysis.validate(workflow)
      assert {:warning, "Tasks with retry but no compensation: [:risky]"} in issues
    end

    test "flags unreachable compensations" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_compensation(:orphan_comp)
        |> Workflow.add_end(:b)
        |> Workflow.connect(:a, :b)

      issues = Analysis.validate(workflow)
      assert {:warning, "Unreachable compensation nodes: [:orphan_comp]"} in issues
    end
  end
end
