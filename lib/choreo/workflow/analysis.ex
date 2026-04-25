defmodule Choreo.Workflow.Analysis do
  @moduledoc """
  Analysis functions for `Choreo.Workflow` orchestration diagrams.

  Provides algorithms that answer practical questions about a workflow:

    * What is the critical path? (longest latency chain)
    * Which tasks can run in parallel?
    * What breaks if a task fails? (failure scenarios)
    * Which tasks lack compensations?
    * Where are the bottlenecks? (high latency / high retry)

  ## Further reading

    * [Saga Pattern (Microsoft)](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/saga/saga)
    * [BPMN 2.0 Specification](https://www.omg.org/spec/BPMN/2.0/)
    * [Workflow Patterns Initiative](http://www.workflowpatterns.com/)
  """

  alias Choreo.Workflow
  alias Yog.Traversal.Sort

  @doc """
  Returns all task node IDs reachable from any start node.
  """
  @spec reachable_tasks(Workflow.t()) :: [Yog.node_id()]
  def reachable_tasks(%Workflow{} = workflow) do
    start_ids = Workflow.starts(workflow)

    if start_ids == [] do
      Workflow.nodes(workflow)
    else
      Choreo.Internal.bfs_reachable(workflow.graph, start_ids)
      |> MapSet.to_list()
    end
  end

  @doc """
  Returns nodes that are not reachable from any start node.
  """
  @spec orphan_tasks(Workflow.t()) :: [Yog.node_id()]
  def orphan_tasks(%Workflow{} = workflow) do
    start_ids = Workflow.starts(workflow)

    if start_ids == [] do
      []
    else
      reachable = Choreo.Internal.bfs_reachable(workflow.graph, start_ids)
      all = Workflow.nodes(workflow) |> MapSet.new()
      MapSet.difference(all, reachable) |> MapSet.to_list()
    end
  end

  @doc """
  Returns nodes that cannot reach any end node.
  """
  @spec dead_ends(Workflow.t()) :: [Yog.node_id()]
  def dead_ends(%Workflow{} = workflow) do
    end_ids = Workflow.ends(workflow)

    if end_ids == [] do
      Workflow.nodes(workflow)
    else
      transposed = Yog.transpose(workflow.graph)
      can_reach_end = Choreo.Internal.bfs_reachable(transposed, end_ids)
      all = Workflow.nodes(workflow) |> MapSet.new()
      MapSet.difference(all, can_reach_end) |> MapSet.to_list()
    end
  end

  @doc """
  Finds the longest weighted path from any start to any end.

  Edge weights default to the target task's `:timeout_ms`. Returns
  `{:ok, [id], total_weight}` or `:error` if cyclic or no start→end path.
  """
  @spec critical_path(Workflow.t()) :: {:ok, [Yog.node_id()], number()} | :error
  def critical_path(%Workflow{graph: graph} = workflow) do
    if Yog.cyclic?(graph) do
      :error
    else
      case Sort.topological_sort(graph) do
        {:ok, order} ->
          start_set = Workflow.starts(workflow) |> MapSet.new()
          end_set = Workflow.ends(workflow) |> MapSet.new()
          dp = Choreo.Internal.compute_dp(graph, order, start_set)

          case Choreo.Internal.find_best_end_path(dp, end_set) do
            nil ->
              :error

            {_dist, end_id} ->
              path = Choreo.Internal.reconstruct_path(dp, end_id)
              total = elem(Map.fetch!(dp, end_id), 0)
              {:ok, path, total}
          end

        {:error, :contains_cycle} ->
          :error
      end
    end
  end

  @doc """
  Returns tasks grouped by topological level.

  Tasks at the same level have no dependencies on each other and can
  theoretically run in parallel.
  """
  @spec parallelizable_tasks(Workflow.t()) :: [[Yog.node_id()]]
  def parallelizable_tasks(%Workflow{graph: graph}) do
    if Yog.cyclic?(graph) do
      []
    else
      case Sort.topological_sort(graph) do
        {:ok, order} ->
          levels = compute_levels(graph, order)

          levels
          |> Enum.group_by(fn {_id, level} -> level end)
          |> Enum.sort_by(fn {level, _items} -> level end)
          |> Enum.map(fn {_level, items} -> Enum.map(items, &elem(&1, 0)) end)

        {:error, :contains_cycle} ->
          []
      end
    end
  end

  @doc """
  Returns tasks that have at least one outgoing compensation edge.
  """
  @spec failure_scenarios(Workflow.t()) :: [Yog.node_id()]
  def failure_scenarios(%Workflow{graph: graph, edge_meta: edge_meta}) do
    graph.nodes
    |> Map.keys()
    |> Enum.filter(fn id ->
      graph
      |> Yog.successor_ids(id)
      |> Enum.any?(fn succ ->
        meta = Map.get(edge_meta, {id, succ}, %{})
        meta[:edge_type] == :compensation
      end)
    end)
  end

  @doc """
  Returns tasks that have retry configured but no compensation path.
  """
  @spec missing_compensations(Workflow.t()) :: [Yog.node_id()]
  def missing_compensations(%Workflow{graph: graph, edge_meta: edge_meta}) do
    tasks_with_retry =
      graph.nodes
      |> Enum.filter(fn {_id, data} ->
        data[:node_type] == :task and is_number(data[:retry]) and data[:retry] > 0
      end)
      |> Enum.map(fn {id, _data} -> id end)

    tasks_with_compensation =
      tasks_with_retry
      |> Enum.filter(fn id ->
        graph
        |> Yog.successor_ids(id)
        |> Enum.any?(fn succ ->
          meta = Map.get(edge_meta, {id, succ}, %{})
          meta[:edge_type] == :compensation
        end)
      end)

    tasks_with_retry -- tasks_with_compensation
  end

  @doc """
  Returns high-latency or high-retry task node IDs.

  ## Options

    * `:latency_threshold` — minimum `:timeout_ms` to qualify (default: `10_000`)
    * `:retry_threshold` — minimum `:retry` count to qualify (default: `2`)
  """
  @spec bottlenecks(Workflow.t(), keyword()) :: [Yog.node_id()]
  def bottlenecks(%Workflow{graph: graph}, opts \\ []) do
    latency_threshold = Keyword.get(opts, :latency_threshold, 10_000)
    retry_threshold = Keyword.get(opts, :retry_threshold, 2)

    graph.nodes
    |> Enum.filter(fn {_id, data} ->
      data[:node_type] == :task and
        ((is_number(data[:timeout_ms]) and data[:timeout_ms] >= latency_threshold) or
           (is_number(data[:retry]) and data[:retry] >= retry_threshold))
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Simulates execution and returns estimated total latency per node.

  Assumes sequential execution along the critical path. Parallel paths
  are counted by their longest branch.
  """
  @spec simulate(Workflow.t()) :: %{optional(Yog.node_id()) => map()}
  def simulate(%Workflow{graph: graph} = workflow) do
    if Yog.cyclic?(graph) do
      %{}
    else
      case Sort.topological_sort(graph) do
        {:ok, order} -> do_simulate(graph, order, workflow.edge_meta, %{})
        {:error, :contains_cycle} -> %{}
      end
    end
  end

  @doc """
  Validates a workflow and returns a list of issues.

  Checks for:
    * missing start / end nodes
    * cycles
    * orphan tasks
    * dead-end tasks
    * tasks with retries but no compensations
    * unreachable compensation nodes
  """
  @spec validate(Workflow.t()) :: [{:error | :warning, String.t()}]
  def validate(%Workflow{} = workflow) do
    []
    |> check_starts(workflow)
    |> check_ends(workflow)
    |> check_cycles(workflow)
    |> check_orphans(workflow)
    |> check_dead_ends(workflow)
    |> check_missing_compensations(workflow)
    |> check_unreachable_compensations(workflow)
  end

  # ============================================================================
  # Private helpers — critical path
  # ============================================================================
  # Private helpers — levels
  # ============================================================================

  defp compute_levels(graph, order) do
    Enum.reduce(order, %{}, fn id, acc ->
      preds = Yog.predecessors(graph, id)

      level =
        if preds == [] do
          0
        else
          preds
          |> Enum.map(fn {pred, _weight} -> Map.get(acc, pred, 0) end)
          |> Enum.max()
          |> Kernel.+(1)
        end

      Map.put(acc, id, level)
    end)
  end

  # ============================================================================
  # Private helpers — simulation
  # ============================================================================

  defp do_simulate(_graph, [], _edge_meta, acc), do: acc

  defp do_simulate(graph, [id | rest], edge_meta, acc) do
    data = Yog.node(graph, id) || %{}

    cumulative_latency =
      graph
      |> Yog.predecessors(id)
      |> Enum.map(fn {pred, _weight} ->
        Map.get(acc, pred, %{cumulative_latency: 0}).cumulative_latency
      end)
      |> case do
        [] -> 0
        values -> Enum.max(values)
      end

    task_latency = data[:timeout_ms] || 0
    retry_latency = compute_retry_latency(data)

    total = cumulative_latency + task_latency + retry_latency

    do_simulate(
      graph,
      rest,
      edge_meta,
      Map.put(acc, id, %{
        cumulative_latency: total,
        task_latency: task_latency,
        retry_latency: retry_latency
      })
    )
  end

  defp compute_retry_latency(%{retry: r, retry_backoff_ms: b}) when is_number(r) and r > 0 do
    backoff = if is_number(b), do: b, else: 0
    r * backoff
  end

  defp compute_retry_latency(_), do: 0

  # ============================================================================
  # Private helpers — validation
  # ============================================================================

  defp check_starts(acc, workflow) do
    if Workflow.starts(workflow) == [] do
      [{:error, "No start nodes"} | acc]
    else
      acc
    end
  end

  defp check_ends(acc, workflow) do
    if Workflow.ends(workflow) == [] do
      [{:error, "No end nodes"} | acc]
    else
      acc
    end
  end

  defp check_cycles(acc, workflow) do
    if Yog.cyclic?(workflow.graph) do
      [{:error, "Cycle detected in workflow"} | acc]
    else
      acc
    end
  end

  defp check_orphans(acc, workflow) do
    case orphan_tasks(workflow) do
      [] -> acc
      nodes -> [{:warning, "Orphan tasks: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_dead_ends(acc, workflow) do
    case dead_ends(workflow) do
      [] -> acc
      nodes -> [{:warning, "Dead-end tasks: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_missing_compensations(acc, workflow) do
    case missing_compensations(workflow) do
      [] -> acc
      nodes -> [{:warning, "Tasks with retry but no compensation: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_unreachable_compensations(acc, workflow) do
    unreachable =
      Workflow.compensations(workflow)
      |> Enum.filter(fn id ->
        in_deg = Yog.in_degree(workflow.graph, id)
        in_deg == 0
      end)

    if unreachable == [] do
      acc
    else
      [{:warning, "Unreachable compensation nodes: #{inspect(unreachable)}"} | acc]
    end
  end
end
