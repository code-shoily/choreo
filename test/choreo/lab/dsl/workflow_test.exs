defmodule Choreo.Lab.WorkflowDSLTest do
  use ExUnit.Case

  doctest Choreo.Lab.DSL.Workflow

  import Choreo.Lab.DSL.Workflow

  alias Choreo.Workflow

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.Workflow.taxonomy()

    assert :task in taxonomy.nodes
    assert :finish in taxonomy.nodes
    assert :swimlane in taxonomy.swimlanes
    assert :~> in taxonomy.edges
    assert :failure in taxonomy.edges
    assert :condition in taxonomy.modifiers
    assert :with in taxonomy.options
    assert Choreo.Lab.DSL.Workflow.verbs() == taxonomy
  end

  test "builds a workflow with variable-bound swimlanes, nodes, and edges" do
    flow =
      workflow do
        backend = swimlane("Backend")
        start = begin("Request received")
        validate = task("Validate token", swimlane: backend, timeout_ms: 100, retry: 2)
        authorized = decision("Authorized?")
        accepted = finish("Return 200")
        rejected = finish("Return 403")

        start ~> validate
        validate ~> authorized
        authorized ~> accepted |> condition("yes")
        failure(authorized ~> rejected, "no")
      end

    assert Workflow.starts(flow) == [:start]
    assert Enum.sort(Workflow.ends(flow)) == [:accepted, :rejected]
    assert :validate in Workflow.tasks(flow)
    assert Map.get(flow.graph.nodes, :validate).cluster == "cluster_backend"
    assert Map.get(flow.graph.nodes, :validate).timeout_ms == 100
    assert Map.get(flow.graph.nodes, :validate).retry == 2

    edges = Workflow.edges_with_meta(flow)

    assert Enum.any?(edges, fn
             {:authorized, :accepted, _weight, meta} -> meta.condition == "yes"
             _other -> false
           end)

    assert Enum.any?(edges, fn
             {:authorized, :rejected, _weight, meta} -> meta.edge_type == :failure
             _other -> false
           end)
  end

  test "supports inline constructors for one-off sketches" do
    flow =
      workflow do
        begin("Start") ~> task("Process")
        task("Process") ~> done("Done")
      end

    assert :start in Workflow.starts(flow)
    assert :process in Workflow.tasks(flow)
    assert :done in Workflow.ends(flow)
  end

  test "supports id option while keeping display label" do
    flow =
      workflow do
        entry = start("HTTP Request", id: :request)
        process = step("Route Tenant")
        terminal = end_event("Response Sent", id: :response)

        edge entry ~> process, "dispatch"
        edge process ~> terminal, with: "return"
      end

    assert Workflow.starts(flow) == [:request]
    assert Workflow.ends(flow) == [:response]
    assert Map.get(flow.graph.nodes, :request).label == "HTTP Request"
    assert Map.get(flow.graph.nodes, :response).label == "Response Sent"

    labels =
      Enum.map(Workflow.edges_with_meta(flow), fn {_from, _to, _weight, meta} -> meta.label end)

    assert "dispatch" in labels
    assert "return" in labels
  end

  test "supports typed edge aliases and keyword edge forms" do
    flow =
      workflow do
        process = task("Process Payment", retry: 3)
        retry_step = task("Retry Payment")
        rollback = compensation("Refund Payment", for: process)
        timeout_handler = task("Timeout Handler")
        done = finish("Done")

        retry process ~> retry_step, "temporary failure"
        edge process ~> timeout_handler, timeout: "gateway timeout"
        process ~> rollback |> compensates("payment failed")
        compensation(rollback ~> done, "refunded")
      end

    assert Map.get(flow.graph.nodes, :rollback).target_task == :process

    edge_types =
      Enum.map(Workflow.edges_with_meta(flow), fn {_from, _to, _weight, meta} ->
        meta.edge_type
      end)

    assert :retry in edge_types
    assert :timeout in edge_types
    assert :compensation in edge_types
  end

  test "supports condition and weight modifiers" do
    flow =
      workflow do
        choose = gateway("Choose route")
        fast = task("Fast Path")
        slow = task("Slow Path")

        choose ~> fast |> when_("cache hit") |> weight(10)
        choose ~> slow |> condition("cache miss") |> weight(100)
      end

    assert Enum.any?(Workflow.edges_with_meta(flow), fn
             {:choose, :fast, weight, meta} -> weight == 10 and meta.condition == "cache hit"
             _other -> false
           end)

    assert Enum.any?(Workflow.edges_with_meta(flow), fn
             {:choose, :slow, weight, meta} -> weight == 100 and meta.condition == "cache miss"
             _other -> false
           end)
  end

  test "raises on unknown node variables" do
    assert_raise ArgumentError, ~r/unknown workflow node variable `missing`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Workflow

          workflow do
            entry = start("Start")
            entry ~> missing
          end
        end
      )
    end
  end

  test "raises on unknown swimlane variables" do
    assert_raise ArgumentError, ~r/unknown workflow swimlane variable `backend`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Workflow

          workflow do
            task("Validate", swimlane: backend)
          end
        end
      )
    end
  end
end
