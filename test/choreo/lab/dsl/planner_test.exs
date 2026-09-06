defmodule Choreo.Lab.PlannerDSLTest do
  use ExUnit.Case

  doctest Choreo.Lab.DSL.Planner

  import Choreo.Lab.DSL.Planner

  alias Choreo.Planner

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.Planner.taxonomy()

    assert :task in taxonomy.nodes
    assert :milestone in taxonomy.nodes
    assert :depends_on in taxonomy.edges
    assert :assigned_to in taxonomy.modifiers
    assert :type in taxonomy.modifiers
    assert :with in taxonomy.options
    assert Choreo.Lab.DSL.Planner.verbs() == taxonomy
  end

  test "builds a planner with tasks, ownership, labels, and dependencies" do
    plan =
      planner "Launch v1" do
        v1 = milestone("V1 Launch")
        design = task("Design API", status: :done, estimate_hours: 8)
        build = task("Build Gateway", priority: :high)
        alice = user("Alice", email: "alice@example.com")
        backend = label("backend")

        contains(v1 ~> design)
        contains(v1 ~> build)
        design ~> build |> depends_on("finish design first")
        build ~> alice |> assigned_to()
        build ~> backend |> tagged_with()
      end

    assert plan.name == "Launch v1"
    assert Enum.sort(Planner.children(plan, :v1)) == [:build, :design]
    assert Planner.dependencies(plan, :build) == [:design]
    assert Planner.assignee(plan, :build) == :alice
    assert Planner.assigned_tasks(plan, :alice) == [:build]
    assert Map.get(plan.graph.nodes, :build).priority == :high
    assert Map.get(plan.graph.nodes, :alice).email == "alice@example.com"
  end

  test "supports inline constructors and typed edge forms" do
    plan =
      planner do
        milestone("Beta") ~> task("Invite Users") |> contains()
        task("Build Feature") ~> task("Ship Feature")
        blocks(task("Missing Contract") ~> task("Integrate Client"))
      end

    assert :beta in Enum.map(Planner.milestones(plan), fn {id, _data} -> id end)
    assert Planner.dependencies(plan, :ship_feature) == [:build_feature]
    assert Planner.dependencies(plan, :integrate_client) == [:missing_contract]
  end

  test "supports id option while keeping display title" do
    plan =
      planner do
        kickoff = task("Kickoff", id: :start_here)
        delivery = task("Delivery")

        edge kickoff ~> delivery, with: "finish kickoff"
      end

    assert Map.get(plan.graph.nodes, :start_here).title == "Kickoff"
    assert Planner.dependencies(plan, :delivery) == [:start_here]
  end

  test "supports edge/3 with label and options" do
    plan =
      planner do
        kickoff = task("Kickoff")
        delivery = task("Delivery")

        edge(kickoff ~> delivery, "finish kickoff first", type: :depends_on)
      end

    assert Planner.dependencies(plan, :delivery) == [:kickoff]
  end

  test "supports piped modifiers with options and type/1,2,3 modifiers" do
    plan =
      planner do
        m1 = milestone("Milestone 1")
        t1 = task("Task 1")
        t2 = task("Task 2")
        alice = user("Alice")
        be = label("backend")

        m1 ~> t1 |> contains(label: "includes")
        t1 ~> t2 |> type(:depends_on, "prereq")
        t2 ~> alice |> type(:assigned_to, label: "owner")
        t2 ~> be |> tagged_with()
      end

    assert Planner.children(plan, :m1) == [:t1]
    assert Planner.dependencies(plan, :t2) == [:t1]
    assert Planner.assignee(plan, :t2) == :alice
    assert Planner.tags(plan, :t2) == [:be]
  end

  test "supports standalone node declarations inside DSL" do
    plan =
      planner do
        milestone("Sprint 1")
        task("Write Code")
        user "Bob"
        label("frontend")
      end

    assert :sprint_1 in Enum.map(Planner.milestones(plan), fn {id, _} -> id end)
    assert :write_code in Enum.map(Planner.tasks(plan), fn {id, _} -> id end)
    assert :bob in Enum.map(Planner.users(plan), fn {id, _} -> id end)
    assert :frontend in Enum.map(Planner.labels(plan), fn {id, _} -> id end)
  end

  test "autocomplete stubs raise outside DSL block" do
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      Choreo.Lab.DSL.Planner.task()
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      Choreo.Lab.DSL.Planner.edge()
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      Choreo.Lab.DSL.Planner.on()
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      Choreo.Lab.DSL.Planner.type()
    end
  end

  test "raises on unknown node variables" do
    assert_raise ArgumentError, ~r/unknown planner node variable `missing`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Planner

          planner do
            task = task("Task")
            task ~> missing
          end
        end
      )
    end
  end

  test "supports edge keywords, typed edges, and raises on unsupported statements" do
    plan =
      planner "Q3 Plan" do
        m = milestone("Launch")
        t1 = task("Task 1")
        t2 = task("Task 2")
        t3 = task("Task 3")
        u = user("Alice")
        lbl = label("urgent")

        contains m ~> t1
        edge t2 ~> t1
        edge t2 ~> t1, "depends"
        contains m ~> t2
        depends_on t2 ~> t1
        blocks(t2 ~> t3)
        assigned_to(t1 ~> u)
        tagged_with(t1 ~> lbl)
      end

    assert plan.name == "Q3 Plan"

    assert_raise ArgumentError, ~r/expected planner constructor/, fn ->
      Code.eval_string("""
      import Choreo.Lab.DSL.Planner
      planner do
        x = 999
      end
      """)
    end

    assert_raise ArgumentError, ~r/unsupported statement in planner DSL/, fn ->
      Code.eval_string("""
      import Choreo.Lab.DSL.Planner
      planner do
        bad_statement("test")
      end
      """)
    end
  end
end
