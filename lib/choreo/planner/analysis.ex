defmodule Choreo.Planner.Analysis do
  @moduledoc """
  Graph analysis algorithms for `Choreo.Planner` projects.

  Provides project-management-specific insights:

    * `ready/1` — tasks whose dependencies are all done
    * `blocked/1` — tasks with unresolved dependencies
    * `orphans/1` — tasks not in any milestone
    * `critical_path/2` — longest dependency chain (by estimate)
    * `bottlenecks/1` — tasks ranked by transitive downstream impact
    * `workload_by_assignee/2` — open work grouped by owner
    * `validate/1` — structural integrity checks
  """

  alias Choreo.Planner

  @doc """
  Returns tasks with status `:backlog` or `:todo` whose dependencies
  are all `:done`.

  ## Examples

      iex> project = Choreo.Planner.new()
      ...> |> Choreo.Planner.add_task(:t1, status: :todo)
      iex> [{id, _}] = Choreo.Planner.Analysis.ready(project)
      iex> id
      :t1
  """
  @spec ready(Planner.t()) :: [{Yog.node_id(), map()}]
  def ready(%Planner{} = planner) do
    planner
    |> Planner.tasks()
    |> Enum.filter(fn {id, data} ->
      data[:status] in [:backlog, :todo] and deps_resolved?(planner, id)
    end)
  end

  @doc """
  Returns tasks that have unresolved dependencies or blockers.

  Done and cancelled tasks are excluded.

  ## Examples

      iex> project = Choreo.Planner.new()
      ...> |> Choreo.Planner.add_task(:a, status: :backlog)
      ...> |> Choreo.Planner.add_task(:b, status: :backlog)
      ...> |> Choreo.Planner.depends_on(:a, :b)
      iex> [{id, _}] = Choreo.Planner.Analysis.blocked(project)
      iex> id
      :a
  """
  @spec blocked(Planner.t()) :: [{Yog.node_id(), map()}]
  def blocked(%Planner{} = planner) do
    planner
    |> Planner.tasks()
    |> Enum.filter(fn {id, data} ->
      data[:status] not in [:done, :cancelled] and not deps_resolved?(planner, id)
    end)
  end

  @doc """
  Returns tasks with no `:contains` relationship (not in any milestone).

  ## Examples

      iex> project = Choreo.Planner.new() |> Choreo.Planner.add_task(:t1)
      iex> [{id, _}] = Choreo.Planner.Analysis.orphans(project)
      iex> id
      :t1
  """
  @spec orphans(Planner.t()) :: [{Yog.node_id(), map()}]
  def orphans(%Planner{} = planner) do
    planner
    |> Planner.tasks()
    |> Enum.filter(fn {id, _data} -> Planner.parent(planner, id) == nil end)
  end

  @doc """
  Finds the critical path — the longest chain of dependent work by estimate.

  If a `milestone` is given, only tasks under that milestone are considered.

  Returns `{:ok, path, total_estimate}` or `:error` if the dependency graph
  contains a cycle.

  ## Examples

      iex> project = Choreo.Planner.new()
      ...> |> Choreo.Planner.add_task(:a, estimate_hours: 2)
      ...> |> Choreo.Planner.add_task(:b, estimate_hours: 3)
      ...> |> Choreo.Planner.depends_on(:b, :a)
      iex> {:ok, [:a, :b], total_estimate: 5} = Choreo.Planner.Analysis.critical_path(project)

      iex> project = Choreo.Planner.new()
      ...> |> Choreo.Planner.add_task(:a)
      ...> |> Choreo.Planner.add_task(:b)
      ...> |> Choreo.Planner.add_task(:c)
      ...> |> Choreo.Planner.depends_on(:b, :a)
      ...> |> Choreo.Planner.depends_on(:a, :c)
      ...> |> Choreo.Planner.depends_on(:c, :b)
      iex> Choreo.Planner.Analysis.critical_path(project)
      :error
  """
  @spec critical_path(Planner.t(), keyword()) :: {:ok, [Yog.node_id()], keyword()} | :error
  def critical_path(%Planner{} = planner, opts \\ []) do
    task_ids =
      case Keyword.get(opts, :milestone) do
        nil ->
          Planner.tasks(planner) |> Enum.map(fn {id, _} -> id end) |> MapSet.new()

        m_id ->
          Planner.children(planner, m_id) |> MapSet.new()
      end

    if MapSet.size(task_ids) == 0 do
      {:ok, [], total_estimate: 0}
    else
      dag = weighted_dependency_dag(planner, task_ids)

      case Yog.Traversal.Sort.topological_sort(dag) do
        {:ok, sorted} ->
          {dist, pred} =
            Enum.reduce(sorted, {%{}, %{}}, fn node, acc ->
              update_distances(planner, dag, node, acc)
            end)

          {end_node, max_dist} =
            task_ids
            |> MapSet.to_list()
            |> Enum.map(fn t -> {t, Map.get(dist, t, 0)} end)
            |> Enum.max_by(fn {_, d} -> d end)

          path = reconstruct_path(pred, end_node)
          {:ok, path, total_estimate: max_dist}

        {:error, :contains_cycle} ->
          :error
      end
    end
  end

  @doc """
  Returns tasks sorted by how many other tasks depend on them
  (directly or transitively).

  High count = task blocks a lot of downstream work (bottleneck).

  ## Examples

      iex> project = Choreo.Planner.new()
      ...> |> Choreo.Planner.add_task(:core)
      ...> |> Choreo.Planner.add_task(:a)
      ...> |> Choreo.Planner.add_task(:b)
      ...> |> Choreo.Planner.depends_on(:a, :core)
      ...> |> Choreo.Planner.depends_on(:b, :core)
      iex> [{top_id, top_count} | _rest] = Choreo.Planner.Analysis.bottlenecks(project)
      iex> top_id
      :core
      iex> top_count
      2
  """
  @spec bottlenecks(Planner.t()) :: [{Yog.node_id(), non_neg_integer()}]
  def bottlenecks(%Planner{} = planner) do
    dep_graph = dependency_subgraph(planner)

    planner
    |> Planner.tasks()
    |> Enum.map(fn {id, _data} ->
      reachable = Yog.Traversal.walk(dep_graph, id, :breadth_first)
      count = length(reachable) - 1
      {id, count}
    end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
  end

  @doc """
  Groups open work by assignee with task counts, estimates, and status counts.

  By default this excludes `:done` and `:cancelled` tasks so the result reflects
  remaining workload. Pass `include_done?: true` to include every task. Tasks with
  multiple assignees are counted once for each assignee; unassigned tasks are
  grouped under `:unassigned`.

  ## Examples

      iex> project = Choreo.Planner.new()
      ...> |> Choreo.Planner.add_task(:a, status: :todo, estimate_hours: 2)
      ...> |> Choreo.Planner.add_task(:b, status: :done, estimate_hours: 3)
      ...> |> Choreo.Planner.add_user(:alice)
      ...> |> Choreo.Planner.assign(:a, :alice)
      iex> Choreo.Planner.Analysis.workload_by_assignee(project)
      [alice: %{estimate_hours: 2, status_counts: %{todo: 1}, task_count: 1, tasks: [:a]}]
  """
  @spec workload_by_assignee(Planner.t(), keyword()) :: [
          {Yog.node_id() | :unassigned,
           %{
             task_count: non_neg_integer(),
             tasks: [Yog.node_id()],
             estimate_hours: number(),
             status_counts: %{optional(atom()) => non_neg_integer()}
           }}
        ]
  def workload_by_assignee(%Planner{} = planner, opts \\ []) do
    include_done? = Keyword.get(opts, :include_done?, false)

    planner
    |> Planner.tasks()
    |> Enum.reject(fn {_id, data} ->
      not include_done? and data[:status] in [:done, :cancelled]
    end)
    |> Enum.flat_map(fn {id, data} ->
      assignees =
        case Planner.assignees(planner, id) do
          [] -> [:unassigned]
          ids -> ids
        end

      Enum.map(assignees, fn assignee -> {assignee, id, data} end)
    end)
    |> Enum.group_by(fn {assignee, _id, _data} -> assignee end)
    |> Enum.map(fn {assignee, entries} ->
      tasks = Enum.map(entries, fn {_assignee, id, _data} -> id end)

      estimate_hours =
        Enum.reduce(entries, 0, fn {_assignee, _id, data}, acc -> acc + task_estimate(data) end)

      status_counts =
        entries
        |> Enum.map(fn {_assignee, _id, data} -> data[:status] || :backlog end)
        |> Enum.frequencies()

      {assignee,
       %{
         task_count: length(tasks),
         tasks: tasks,
         estimate_hours: estimate_hours,
         status_counts: status_counts
       }}
    end)
    |> Enum.sort_by(fn {assignee, summary} ->
      {-summary.estimate_hours, -summary.task_count, inspect(assignee)}
    end)
  end

  @doc """
  Evaluates the planner and returns a list of human-readable warnings and errors.

  ## Examples

      iex> project = Choreo.Planner.new() |> Choreo.Planner.add_task(:a, status: :in_progress)
      iex> Choreo.Planner.Analysis.validate(project)
      [
        {:warning, "Task :a is in progress but has no assignee"},
        {:warning, "Task :a is not in any milestone"}
      ]

      iex> project = Choreo.Planner.new()
      ...> |> Choreo.Planner.add_task(:a)
      ...> |> Choreo.Planner.add_task(:b)
      ...> |> Choreo.Planner.add_task(:c)
      ...> |> Choreo.Planner.depends_on(:b, :a)
      ...> |> Choreo.Planner.depends_on(:a, :c)
      ...> |> Choreo.Planner.depends_on(:c, :b)
      iex> [{:error, msg} | _] = Choreo.Planner.Analysis.validate(project)
      iex> String.contains?(msg, "Cycle detected")
      true
  """
  @spec validate(Planner.t()) :: [{:error | :warning, String.t()}]
  def validate(%Planner{} = planner) do
    planner
    |> validate_raw()
    |> Enum.map(&format_message/1)
  end

  defp validate_raw(%Planner{} = planner) do
    issues = []

    dep_graph = dependency_subgraph(planner)

    issues =
      if Yog.Property.Cyclicity.cyclic?(dep_graph) do
        [{:error, :cycle_detected, cycle_nodes(dep_graph)} | issues]
      else
        issues
      end

    issues =
      planner
      |> Planner.tasks()
      |> Enum.filter(fn {id, data} ->
        data[:status] == :in_progress and Planner.assignee(planner, id) == nil
      end)
      |> Enum.reduce(issues, fn {id, _data}, acc ->
        [{:warning, :unassigned_in_progress, id} | acc]
      end)

    issues =
      planner
      |> Planner.tasks()
      |> Enum.filter(fn {id, _data} ->
        Planner.parents(planner, id) == []
      end)
      |> Enum.reduce(issues, fn {id, _data}, acc ->
        [{:warning, :orphan_task, id} | acc]
      end)

    issues =
      planner
      |> Planner.milestones()
      |> Enum.filter(fn {id, _data} ->
        Planner.children(planner, id) == []
      end)
      |> Enum.reduce(issues, fn {id, _data}, acc ->
        [{:warning, :empty_milestone, id} | acc]
      end)

    Enum.reverse(issues)
  end

  @doc """
  Converts validation 3-tuples to standard 2-tuples with human-readable messages.
  """
  @spec validate_messages(Planner.t()) :: [{:error | :warning, String.t()}]
  def validate_messages(%Planner{} = planner) do
    validate(planner)
  end

  defp format_message({:error, :cycle_detected, nodes}) do
    {:error, "Cycle detected among: #{Enum.map_join(nodes, ", ", &inspect/1)}"}
  end

  defp format_message({:warning, :unassigned_in_progress, id}) do
    {:warning, "Task #{inspect(id)} is in progress but has no assignee"}
  end

  defp format_message({:warning, :orphan_task, id}) do
    {:warning, "Task #{inspect(id)} is not in any milestone"}
  end

  defp format_message({:warning, :empty_milestone, id}) do
    {:warning, "Milestone #{inspect(id)} has no tasks"}
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp deps_resolved?(%Planner{} = planner, id) do
    planner
    |> Planner.dependencies(id)
    |> Enum.all?(fn dep_id ->
      case planner.graph.nodes[dep_id] do
        nil -> true
        data -> data[:status] == :done
      end
    end)
  end

  defp reconstruct_path(pred, node, acc \\ []) do
    case Map.get(pred, node) do
      nil -> [node | acc]
      parent -> reconstruct_path(pred, parent, [node | acc])
    end
  end

  defp dependency_subgraph(planner) do
    g = planner.graph
    simple = Yog.directed()

    simple =
      Enum.reduce(g.nodes, simple, fn {id, _data}, acc ->
        Yog.Model.add_node(acc, id, nil)
      end)

    Enum.reduce(g.edges, simple, fn {eid, {from, to, _weight}}, acc ->
      meta = planner.edge_meta[eid] || %{}

      if meta[:type] in [:depends_on, :blocks] do
        case Yog.Model.add_edge(acc, from, to, nil) do
          {:ok, g} -> g
          {:error, _} -> acc
        end
      else
        acc
      end
    end)
  end

  defp weighted_dependency_dag(planner, allowed_nodes) do
    g = planner.graph
    simple = Yog.directed()

    simple =
      Enum.reduce(g.nodes, simple, fn {id, _data}, acc ->
        if id in allowed_nodes do
          Yog.Model.add_node(acc, id, nil)
        else
          acc
        end
      end)

    Enum.reduce(g.edges, simple, fn {eid, {from, to, _weight}}, acc ->
      meta = planner.edge_meta[eid] || %{}

      if meta[:type] in [:depends_on, :blocks] and from in allowed_nodes and to in allowed_nodes do
        weight = task_estimate(planner, to)

        case Yog.Model.add_edge(acc, from, to, weight) do
          {:ok, g} -> g
          {:error, _} -> acc
        end
      else
        acc
      end
    end)
  end

  defp update_distances(planner, dag, node, {dist_acc, pred_acc}) do
    weighted_preds = Yog.Model.predecessors(dag, node)

    if weighted_preds == [] do
      weight = task_estimate(planner, node)
      {Map.put(dist_acc, node, weight), pred_acc}
    else
      {best_pred, best_dist} =
        weighted_preds
        |> Enum.map(fn {p, weight} -> {p, Map.get(dist_acc, p, 0) + weight} end)
        |> Enum.max_by(fn {_, d} -> d end)

      {
        Map.put(dist_acc, node, best_dist),
        Map.put(pred_acc, node, best_pred)
      }
    end
  end

  defp task_estimate(%Planner{graph: g}, id) do
    case g.nodes[id] do
      data when is_map(data) -> task_estimate(data)
      _ -> 1
    end
  end

  defp task_estimate(%{estimate_hours: hrs}) when is_number(hrs) and hrs > 0, do: hrs
  defp task_estimate(_data), do: 1

  defp cycle_nodes(g) do
    case Yog.Traversal.Sort.topological_sort(g) do
      {:ok, _} ->
        []

      {:error, :contains_cycle} ->
        g
        |> Yog.Connectivity.SCC.strongly_connected_components()
        |> Enum.filter(fn comp -> length(comp) > 1 end)
        |> List.flatten()
    end
  end
end
