defmodule Choreo.Planner.AnalysisTest do
  use ExUnit.Case

  alias Choreo.Planner
  alias Choreo.Planner.Analysis

  doctest Choreo.Planner.Analysis

  describe "ready/1" do
    test "returns tasks with all dependencies done" do
      project =
        Planner.new()
        |> Planner.add_task(:design, status: :done)
        |> Planner.add_task(:impl, status: :todo)
        |> Planner.add_task(:test, status: :backlog)
        |> Planner.depends_on(:impl, :design)
        |> Planner.depends_on(:test, :impl)

      assert [{:impl, _}] = Analysis.ready(project)
    end

    test "returns empty when nothing is ready" do
      project =
        Planner.new()
        |> Planner.add_task(:a, status: :backlog)
        |> Planner.add_task(:b, status: :backlog)
        |> Planner.depends_on(:b, :a)

      # :a is ready (no deps), :b is not
      assert [{:a, _}] = Analysis.ready(project)
    end
  end

  describe "blocked/1" do
    test "returns tasks with unresolved dependencies" do
      project =
        Planner.new()
        |> Planner.add_task(:a, status: :backlog)
        |> Planner.add_task(:b, status: :in_progress)
        |> Planner.depends_on(:b, :a)

      assert [{:b, _}] = Analysis.blocked(project)
    end

    test "excludes done and cancelled tasks" do
      project =
        Planner.new()
        |> Planner.add_task(:a, status: :done)
        |> Planner.add_task(:b, status: :cancelled)
        |> Planner.depends_on(:b, :a)

      assert Analysis.blocked(project) == []
    end
  end

  describe "orphans/1" do
    test "returns tasks not in any milestone" do
      project =
        Planner.new()
        |> Planner.add_milestone(:v1)
        |> Planner.add_task(:a)
        |> Planner.add_task(:b)
        |> Planner.contains(:v1, :a)

      assert [{:b, _}] = Analysis.orphans(project)
    end
  end

  describe "critical_path/2" do
    test "finds longest dependency chain" do
      project =
        Planner.new()
        |> Planner.add_task(:a, estimate_hours: 2)
        |> Planner.add_task(:b, estimate_hours: 3)
        |> Planner.add_task(:c, estimate_hours: 1)
        |> Planner.depends_on(:b, :a)
        |> Planner.depends_on(:c, :b)

      assert {:ok, [:a, :b, :c], total_estimate: 6} = Analysis.critical_path(project)
    end

    test "scoped to milestone" do
      project =
        Planner.new()
        |> Planner.add_milestone(:v1)
        |> Planner.add_task(:a, estimate_hours: 2)
        |> Planner.add_task(:b, estimate_hours: 3)
        |> Planner.add_task(:c, estimate_hours: 1)
        |> Planner.contains(:v1, :a)
        |> Planner.contains(:v1, :b)
        |> Planner.depends_on(:b, :a)

      assert {:ok, [:a, :b], total_estimate: 5} = Analysis.critical_path(project, milestone: :v1)
    end

    test "returns error on cycle" do
      project =
        Planner.new()
        |> Planner.add_task(:a)
        |> Planner.add_task(:b)
        |> Planner.add_task(:c)
        |> Planner.depends_on(:b, :a)
        |> Planner.depends_on(:a, :c)
        |> Planner.depends_on(:c, :b)

      assert :error = Analysis.critical_path(project)
    end

    test "returns empty for no tasks" do
      project = Planner.new()
      assert {:ok, [], total_estimate: 0} = Analysis.critical_path(project)
    end
  end

  describe "bottlenecks/1" do
    test "ranks tasks by downstream impact" do
      project =
        Planner.new()
        |> Planner.add_task(:core)
        |> Planner.add_task(:a)
        |> Planner.add_task(:b)
        |> Planner.add_task(:c)
        |> Planner.depends_on(:a, :core)
        |> Planner.depends_on(:b, :core)
        |> Planner.depends_on(:c, :a)

      assert [{:core, 3}, {:a, 1}, {:b, 0}, {:c, 0}] = Analysis.bottlenecks(project)
    end
  end

  describe "validate/1" do
    test "detects cycles" do
      project =
        Planner.new()
        |> Planner.add_milestone(:v1)
        |> Planner.add_task(:a)
        |> Planner.add_task(:b)
        |> Planner.add_task(:c)
        |> Planner.contains(:v1, :a)
        |> Planner.contains(:v1, :b)
        |> Planner.contains(:v1, :c)
        |> Planner.depends_on(:b, :a)
        |> Planner.depends_on(:a, :c)
        |> Planner.depends_on(:c, :b)

      assert [{:error, msg}] = Analysis.validate(project)
      assert msg =~ "Cycle detected"
    end

    test "warns about unassigned in-progress tasks" do
      project =
        Planner.new()
        |> Planner.add_milestone(:v1)
        |> Planner.add_task(:a, status: :in_progress)
        |> Planner.contains(:v1, :a)

      assert [{:warning, msg}] = Analysis.validate(project)
      assert msg =~ "has no assignee"
    end

    test "returns empty for valid project" do
      project =
        Planner.new()
        |> Planner.add_milestone(:v1)
        |> Planner.add_task(:a, status: :done)
        |> Planner.add_user(:alice)
        |> Planner.assign(:a, :alice)
        |> Planner.contains(:v1, :a)

      assert Analysis.validate(project) == []
    end
  end
end
