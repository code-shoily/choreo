defmodule Choreo.Planner.Analysis do
  @moduledoc """
  Graph analysis algorithms for `Choreo.Planner` projects.

  Provides project-management-specific insights:

    * `ready/1` — tasks whose dependencies are all done
    * `blocked/1` — tasks with unresolved dependencies
    * `orphans/1` — tasks not in any milestone
    * `critical_path/2` — longest dependency chain (by estimate)
    * `bottlenecks/1` — tasks ranked by transitive downstream impact
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
  @spec ready(Planner.t()) :: [{Planner.t(), map()}]
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
  @spec blocked(Planner.t()) :: [{Planner.t(), map()}]
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
  @spec orphans(Planner.t()) :: [{Planner.t(), map()}]
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
  @spec critical_path(Planner.t(), keyword()) :: {:ok, [Planner.t()], keyword()} | :error
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
  @spec bottlenecks(Planner.t()) :: [{Planner.t(), non_neg_integer()}]
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
  Validates structural integrity.

  Returns a list of issues like `{:error, :cycle_detected, nodes}` or
  `{:warning, :unassigned_in_progress, task_id}`.

  ## Examples

      iex> project = Choreo.Planner.new() |> Choreo.Planner.add_task(:a, status: :in_progress)
      iex> Choreo.Planner.Analysis.validate(project)
      [{:warning, :unassigned_in_progress, :a}]

      iex> project = Choreo.Planner.new()
      ...> |> Choreo.Planner.add_task(:a)
      ...> |> Choreo.Planner.add_task(:b)
      ...> |> Choreo.Planner.add_task(:c)
      ...> |> Choreo.Planner.depends_on(:b, :a)
      ...> |> Choreo.Planner.depends_on(:a, :c)
      ...> |> Choreo.Planner.depends_on(:c, :b)
      iex> [{:error, :cycle_detected, nodes}] = Choreo.Planner.Analysis.validate(project)
      iex> is_list(nodes)
      true
      iex> :a in nodes
      true
  """
  @spec validate(Planner.t()) :: list()
  def validate(%Planner{} = planner) do
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

    Enum.reverse(issues)
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
    preds = predecessors(dag, node)
    weight = task_estimate(planner, node)

    if preds == [] do
      {Map.put(dist_acc, node, weight), pred_acc}
    else
      {best_pred, best_dist} =
        preds
        |> Enum.map(fn p -> {p, Map.get(dist_acc, p, 0) + weight} end)
        |> Enum.max_by(fn {_, d} -> d end)

      {
        Map.put(dist_acc, node, best_dist),
        Map.put(pred_acc, node, best_pred)
      }
    end
  end

  defp task_estimate(%Planner{graph: g}, id) do
    case g.nodes[id] do
      %{estimate_hours: hrs} when is_number(hrs) and hrs > 0 -> hrs
      _ -> 1
    end
  end

  defp predecessors(dag, node) do
    dag
    |> Yog.Model.predecessors(node)
    |> Enum.map(fn {from, _weight} -> from end)
  end

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
