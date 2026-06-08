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

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_task(:b)
      ...>   |> Choreo.Workflow.add_task(:c)
      ...>   |> Choreo.Workflow.connect(:a, :b)
      iex> Enum.sort(Choreo.Workflow.Analysis.reachable_tasks(workflow))
      [:a, :b]

  This analysis answers the question: "Which tasks are reachable from any start node?"
  """
  @spec reachable_tasks(Workflow.t()) :: [Yog.node_id()]
  def reachable_tasks(%Workflow{} = workflow) do
    start_ids = Workflow.starts(workflow)
    simple_graph = Workflow.to_simple_graph(workflow)

    if start_ids == [] do
      Workflow.nodes(workflow)
    else
      Choreo.Internal.bfs_reachable(simple_graph, start_ids)
      |> MapSet.to_list()
    end
  end

  @doc """
  Returns nodes that are not reachable from any start node.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_task(:b)
      ...>   |> Choreo.Workflow.add_task(:orphan)
      ...>   |> Choreo.Workflow.connect(:a, :b)
      iex> Choreo.Workflow.Analysis.orphan_tasks(workflow)
      [:orphan]

  This analysis answers the question: "Which tasks are not reachable from any start node?"
  """
  @spec orphan_tasks(Workflow.t()) :: [Yog.node_id()]
  def orphan_tasks(%Workflow{} = workflow) do
    start_ids = Workflow.starts(workflow)
    simple_graph = Workflow.to_simple_graph(workflow)

    if start_ids == [] do
      []
    else
      reachable = Choreo.Internal.bfs_reachable(simple_graph, start_ids)
      all = Workflow.nodes(workflow) |> MapSet.new()
      MapSet.difference(all, reachable) |> MapSet.to_list()
    end
  end

  @doc """
  Returns nodes that cannot reach any end node.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_task(:b)
      ...>   |> Choreo.Workflow.add_task(:dead)
      ...>   |> Choreo.Workflow.add_end(:finish)
      ...>   |> Choreo.Workflow.connect(:a, :b)
      ...>   |> Choreo.Workflow.connect(:b, :finish)
      iex> Choreo.Workflow.Analysis.dead_ends(workflow)
      [:dead]

  This analysis answers the question: "Which tasks can never reach an end node?"
  """
  @spec dead_ends(Workflow.t()) :: [Yog.node_id()]
  def dead_ends(%Workflow{} = workflow) do
    end_ids = Workflow.ends(workflow)
    simple_graph = Workflow.to_simple_graph(workflow)

    if end_ids == [] do
      []
    else
      transposed = Yog.transpose(simple_graph)
      can_reach_end = Choreo.Internal.bfs_reachable(transposed, end_ids)
      all = Workflow.nodes(workflow) |> MapSet.new()
      MapSet.difference(all, can_reach_end) |> MapSet.to_list() |> Enum.sort()
    end
  end

  @doc """
  Finds the longest weighted path from any start to any end.

  Edge weights default to the target task's `:timeout_ms`. Returns
  `{:ok, [id], total_weight}` or `:error` if cyclic or no start→end path.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_task(:b, timeout_ms: 10)
      ...>   |> Choreo.Workflow.add_task(:c, timeout_ms: 5)
      ...>   |> Choreo.Workflow.add_end(:d)
      ...>   |> Choreo.Workflow.connect(:a, :b)
      ...>   |> Choreo.Workflow.connect(:b, :c)
      ...>   |> Choreo.Workflow.connect(:c, :d)
      iex> Choreo.Workflow.Analysis.critical_path(workflow)
      {:ok, [:a, :b, :c, :d], 16}

  This analysis answers the question: "What is the slowest end-to-end execution path?"
  """
  @spec critical_path(Workflow.t()) :: {:ok, [Yog.node_id()], number()} | :error
  def critical_path(%Workflow{} = workflow) do
    simple_graph = Workflow.to_simple_graph(workflow, combine: &max/2)

    if Yog.cyclic?(simple_graph) do
      :error
    else
      case Sort.topological_sort(simple_graph) do
        {:ok, order} ->
          start_set = Workflow.starts(workflow) |> MapSet.new()
          end_set = Workflow.ends(workflow) |> MapSet.new()
          dp = Choreo.Internal.compute_dp(simple_graph, order, start_set)

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

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:start)
      ...>   |> Choreo.Workflow.add_fork(:split)
      ...>   |> Choreo.Workflow.add_task(:a)
      ...>   |> Choreo.Workflow.add_task(:b)
      ...>   |> Choreo.Workflow.add_join(:merge)
      ...>   |> Choreo.Workflow.add_end(:end)
      ...>   |> Choreo.Workflow.connect(:start, :split)
      ...>   |> Choreo.Workflow.connect(:split, :a)
      ...>   |> Choreo.Workflow.connect(:split, :b)
      ...>   |> Choreo.Workflow.connect(:a, :merge)
      ...>   |> Choreo.Workflow.connect(:b, :merge)
      ...>   |> Choreo.Workflow.connect(:merge, :end)
      iex> groups = Choreo.Workflow.Analysis.parallelizable_tasks(workflow)
      iex> Enum.any?(groups, fn g -> Enum.sort(g) == [:a, :b] end)
      true

  This analysis answers the question: "Which tasks can run in parallel?"
  """
  @spec parallelizable_tasks(Workflow.t()) :: [[Yog.node_id()]]
  def parallelizable_tasks(%Workflow{} = workflow) do
    simple_graph = Workflow.to_simple_graph(workflow)

    if Yog.cyclic?(simple_graph) do
      []
    else
      case Sort.topological_sort(simple_graph) do
        {:ok, order} ->
          levels = compute_levels(simple_graph, order)

          levels
          |> Enum.filter(fn {id, _level} ->
            (Yog.node(simple_graph, id) || %{})[:node_type] == :task
          end)
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

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_task(:process)
      ...>   |> Choreo.Workflow.add_compensation(:rollback)
      ...>   |> Choreo.Workflow.connect(:process, :rollback, edge_type: :compensation)
      iex> Choreo.Workflow.Analysis.compensable_tasks(workflow)
      [:process]

  This analysis answers the question: "Which tasks have compensation handlers?"
  """
  @spec compensable_tasks(Workflow.t()) :: [Yog.node_id()]
  def compensable_tasks(%Workflow{graph: graph, edge_meta: edge_meta}) do
    graph.nodes
    |> Map.keys()
    |> Enum.filter(fn id ->
      Yog.Multi.successors(graph, id)
      |> Enum.any?(fn {_to, edge_id, _label} ->
        meta = Map.get(edge_meta, edge_id, %{})
        meta[:edge_type] == :compensation
      end)
    end)
  end

  @doc false
  @deprecated "Use compensable_tasks/1 instead"
  def failure_scenarios(workflow), do: compensable_tasks(workflow)

  @doc """
  Returns tasks that can fail but have no valid compensation path.

  A task "can fail" if it has an outgoing `:error` edge.
  A valid compensation path is an unbroken chain of `:compensation` edges
  that terminates (reaches a node with no further outgoing `:compensation`
  edges). The terminus need not be a `:start` or `:end` node.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:start)
      ...>   |> Choreo.Workflow.add_task(:process_payment)
      ...>   |> Choreo.Workflow.add_compensation(:rollback_payment, for: :process_payment)
      ...>   |> Choreo.Workflow.add_task(:dead_end_comp)
      ...>   |> Choreo.Workflow.add_end(:done)
      ...>   |> Choreo.Workflow.connect(:start, :process_payment)
      ...>   |> Choreo.Workflow.connect(:process_payment, :done)
      ...>   |> Choreo.Workflow.connect(:process_payment, :rollback_payment, edge_type: :error)
      ...>   |> Choreo.Workflow.connect(:rollback_payment, :dead_end_comp, edge_type: :compensation)
      iex> Choreo.Workflow.Analysis.uncompensated_paths(workflow)
      []

  This analysis answers the question: "Which tasks can fail without a valid compensation path?"

  A compensation chain is valid if it terminates (reaches a node with no
  further outgoing `:compensation` edges). The example above terminates at
  `:dead_end_comp`, so `:process_payment` is considered compensated.
  """
  @spec uncompensated_paths(Workflow.t()) :: [Yog.node_id()]
  def uncompensated_paths(%Workflow{graph: graph, edge_meta: edge_meta}) do
    can_fail =
      graph.nodes
      |> Enum.filter(fn {id, _data} ->
        Yog.Multi.successors(graph, id)
        |> Enum.any?(fn {_succ, edge_id, _label} ->
          meta = Map.get(edge_meta, edge_id, %{})
          meta[:edge_type] == :error
        end)
      end)
      |> Enum.map(fn {id, _data} -> id end)

    comp_graph =
      Enum.reduce(graph.edges, Yog.directed(), fn {edge_id, {src, dst, weight}}, acc ->
        meta = Map.get(edge_meta, edge_id, %{})

        if meta[:edge_type] == :compensation do
          acc
          |> Yog.add_node(src, Map.get(graph.nodes, src))
          |> Yog.add_node(dst, Map.get(graph.nodes, dst))
          |> Yog.add_edge_ensure(src, dst, weight)
        else
          acc
        end
      end)

    can_fail
    |> Enum.reject(fn id ->
      error_targets =
        Yog.Multi.successors(graph, id)
        |> Enum.filter(fn {_succ, edge_id, _label} ->
          meta = Map.get(edge_meta, edge_id, %{})
          meta[:edge_type] == :error
        end)
        |> Enum.map(fn {succ, _edge_id, _label} -> succ end)

      Enum.all?(error_targets, fn target ->
        reachable = Choreo.Internal.bfs_reachable(comp_graph, [target])

        Enum.any?(reachable, fn node ->
          Yog.out_degree(comp_graph, node) == 0
        end)
      end)
    end)
  end

  @doc """
  Returns tasks that have retry configured but no compensation path.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_task(:risky, retry: 3)
      ...>   |> Choreo.Workflow.add_task(:safe, retry: 2)
      ...>   |> Choreo.Workflow.add_compensation(:rollback, for: :safe)
      ...>   |> Choreo.Workflow.add_end(:end)
      ...>   |> Choreo.Workflow.connect(:a, :risky)
      ...>   |> Choreo.Workflow.connect(:risky, :safe)
      ...>   |> Choreo.Workflow.connect(:safe, :end)
      ...>   |> Choreo.Workflow.connect(:safe, :rollback, edge_type: :compensation)
      iex> Choreo.Workflow.Analysis.missing_compensations(workflow)
      [:risky]

  This analysis answers the question: "Which retry-configured tasks lack compensations?"
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
        Yog.Multi.successors(graph, id)
        |> Enum.any?(fn {_succ, edge_id, _label} ->
          meta = Map.get(edge_meta, edge_id, %{})
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

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_task(:fast, timeout_ms: 100)
      ...>   |> Choreo.Workflow.add_task(:slow, timeout_ms: 20_000)
      iex> Choreo.Workflow.Analysis.bottlenecks(workflow, latency_threshold: 10_000)
      [:slow]

  This analysis answers the question: "Which tasks are high-latency or high-retry?"
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

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_task(:b, timeout_ms: 5000)
      ...>   |> Choreo.Workflow.add_task(:c, timeout_ms: 3000, retry: 2, retry_backoff_ms: 100)
      ...>   |> Choreo.Workflow.add_end(:d)
      ...>   |> Choreo.Workflow.connect(:a, :b)
      ...>   |> Choreo.Workflow.connect(:b, :c)
      ...>   |> Choreo.Workflow.connect(:c, :d)
      iex> result = Choreo.Workflow.Analysis.simulate(workflow)
      iex> result[:b].task_latency
      5000
      iex> result[:c].task_latency
      3000
      iex> result[:c].cumulative_latency
      8000

  This analysis answers the question: "What is the estimated latency for each task?"

  Retry latency is not included — simulate models the happy path.
  Use `critical_path/1` for worst-case latency including retries.
  """
  @spec simulate(Workflow.t()) :: %{optional(Yog.node_id()) => map()}
  def simulate(%Workflow{} = workflow) do
    simple_graph = Workflow.to_simple_graph(workflow, combine: &max/2)

    if Yog.cyclic?(simple_graph) do
      %{}
    else
      case Sort.topological_sort(simple_graph) do
        {:ok, order} -> do_simulate(simple_graph, order, workflow.edge_meta, %{})
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

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_task(:b)
      ...>   |> Choreo.Workflow.add_end(:c)
      ...>   |> Choreo.Workflow.connect(:a, :b)
      ...>   |> Choreo.Workflow.connect(:b, :c)
      iex> Choreo.Workflow.Analysis.validate(workflow)
      []

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_task(:a)
      ...>   |> Choreo.Workflow.add_end(:b)
      ...>   |> Choreo.Workflow.connect(:a, :b)
      iex> issues = Choreo.Workflow.Analysis.validate(workflow)
      iex> {:error, "No start nodes"} in issues
      true

  This analysis answers the question: "Is the workflow structurally sound?"
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
    |> check_invalid_compensation_references(workflow)
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
    total = cumulative_latency + task_latency

    do_simulate(
      graph,
      rest,
      edge_meta,
      Map.put(acc, id, %{
        cumulative_latency: total,
        task_latency: task_latency
      })
    )
  end

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
    sequence_graph = sequence_only_simple_graph(workflow)

    if Yog.cyclic?(sequence_graph) do
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
    simple_graph = Workflow.to_simple_graph(workflow)

    unreachable =
      Workflow.compensations(workflow)
      |> Enum.filter(fn id ->
        in_deg = Yog.in_degree(simple_graph, id)
        in_deg == 0
      end)

    if unreachable == [] do
      acc
    else
      [{:warning, "Unreachable compensation nodes: #{inspect(unreachable)}"} | acc]
    end
  end

  defp check_invalid_compensation_references(acc, %Workflow{graph: graph}) do
    invalid =
      graph.nodes
      |> Enum.filter(fn {_id, data} ->
        data[:node_type] == :compensation and
          data[:target_task] != nil and
          not Map.has_key?(graph.nodes, data[:target_task])
      end)
      |> Enum.map(fn {id, data} ->
        {:warning,
         "Compensation #{inspect(id)} references unknown task #{inspect(data[:target_task])}"}
      end)

    invalid ++ acc
  end

  defp sequence_only_simple_graph(%Workflow{graph: graph, edge_meta: edge_meta}) do
    graph.edges
    |> Enum.reduce(Yog.directed(), fn {edge_id, {src, dst, weight}}, acc ->
      meta = Map.get(edge_meta, edge_id, %{})

      if meta[:edge_type] == :sequence do
        acc
        |> Yog.add_node(src, Map.get(graph.nodes, src))
        |> Yog.add_node(dst, Map.get(graph.nodes, dst))
        |> Yog.add_edge_ensure(src, dst, weight)
      else
        acc
      end
    end)
  end

  @doc """
  Generates a heatmap of the workflow based on cumulative execution latency.

  Nodes with higher total latency (including retries and backoffs) will be
  colored with "hotter" colors.

  ## Options
    * `:palette` — Color palette (`:heat`, `:cool`, `:spectral`)
  """
  @spec heatmap(Workflow.t(), keyword()) :: Workflow.t()
  def heatmap(%Workflow{} = workflow, opts \\ []) do
    simulation = simulate(workflow)

    scores =
      simulation
      |> Enum.map(fn {id, stats} -> {id, stats.cumulative_latency} end)

    Choreo.Analysis.heatmap(workflow, Keyword.put(opts, :scores, scores))
  end
end
