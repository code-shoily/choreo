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
end
