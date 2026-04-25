defmodule Choreo.Dependency.Analysis do
  @moduledoc """
  Analysis functions for `Choreo.Dependency` graphs.

  Provides algorithms that answer practical questions about a codebase:

    * Where are the circular dependencies?
    * What breaks if I change a component?
    * Are we violating our layer architecture?
    * Which components are most coupled?
    * What is the deepest dependency chain?
  """

  alias Choreo.Dependency

  @doc """
  Returns all circular dependency chains.

  Each cycle is returned as a list of node IDs starting and ending at the
  same node. Only one representative cycle is returned per strongly
  connected component.

  ## Examples

      deps =
        Choreo.Dependency.new()
        |> Choreo.Dependency.add_module(:a)
        |> Choreo.Dependency.add_module(:b)
        |> Choreo.Dependency.add_module(:c)
        |> Choreo.Dependency.depends_on(:a, :b)
        |> Choreo.Dependency.depends_on(:b, :a)
        |> Choreo.Dependency.depends_on(:c, :a)

      Choreo.Dependency.Analysis.cyclic_dependencies(deps)
      #=> [[:a, :b, :a]]
  """
  @spec cyclic_dependencies(Dependency.t()) :: [[Yog.node_id()]]
  def cyclic_dependencies(%Dependency{graph: graph}) do
    sccs = Yog.Connectivity.scc(graph)

    sccs
    |> Enum.filter(fn component -> length(component) > 1 end)
    |> Enum.map(fn component ->
      start = hd(component)
      find_cycle(graph, start, start, MapSet.new([start]), [start])
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Returns all nodes that transitively depend on the given node.

  If you change `target`, these are the components that could break.

  ## Examples

      deps =
        Choreo.Dependency.new()
        |> Choreo.Dependency.add_application(:api)
        |> Choreo.Dependency.add_module(:auth)
        |> Choreo.Dependency.add_module(:util)
        |> Choreo.Dependency.depends_on(:api, :auth)
        |> Choreo.Dependency.depends_on(:auth, :util)

      Choreo.Dependency.Analysis.affected_by(deps, :util)
      #=> [:auth, :api]
  """
  @spec affected_by(Dependency.t(), Yog.node_id()) :: [Yog.node_id()]
  def affected_by(%Dependency{graph: graph}, target) do
    transposed = Yog.transpose(graph)

    Choreo.Internal.bfs_reachable(transposed, [target])
    |> MapSet.to_list()
    |> List.delete(target)
  end

  @doc """
  Returns all nodes that the given node transitively depends on.

  These are the components `target` cannot function without.

  ## Examples

      Choreo.Dependency.Analysis.depends_on(deps, :api)
      #=> [:auth, :util]
  """
  @spec depends_on(Dependency.t(), Yog.node_id()) :: [Yog.node_id()]
  def depends_on(%Dependency{graph: graph}, target) do
    Choreo.Internal.bfs_reachable(graph, [target])
    |> MapSet.to_list()
    |> List.delete(target)
  end

  @doc """
  Checks edges against an expected layered architecture.

  `layers` is a map of `node_id => layer_index` where lower numbers are
  "lower" layers (foundations). A violation occurs when an edge points
  from a lower layer to a higher layer (the dependency arrow goes
  upward).

  Returns a list of violation tuples: `{from, to, description}`.

  ## Examples

      layers = %{repo: 1, service: 2, api: 3}

      deps =
        Choreo.Dependency.new()
        |> Choreo.Dependency.add_module(:repo)
        |> Choreo.Dependency.add_module(:service)
        |> Choreo.Dependency.add_module(:api)
        |> Choreo.Dependency.depends_on(:service, :repo)
        |> Choreo.Dependency.depends_on(:repo, :api)  # violation!

      Choreo.Dependency.Analysis.layer_violations(deps, layers)
      #=> [{:repo, :api, "repo (layer 1) -> api (layer 3)"}]
  """
  @spec layer_violations(Dependency.t(), %{Yog.node_id() => integer()}) :: [
          {Yog.node_id(), Yog.node_id(), String.t()}
        ]
  def layer_violations(%Dependency{graph: graph}, layers) do
    graph
    |> Yog.all_edges()
    |> Enum.flat_map(fn {from, to, _label} ->
      from_layer = Map.get(layers, from)
      to_layer = Map.get(layers, to)

      if from_layer != nil and to_layer != nil and from_layer < to_layer do
        desc = "#{from} (layer #{from_layer}) -> #{to} (layer #{to_layer})"
        [{from, to, desc}]
      else
        []
      end
    end)
  end

  @doc """
  Returns nodes ranked by coupling centrality (in-degree + out-degree).

  The most coupled components are at the head of the list.

  ## Options

    * `:limit` — maximum number of results (default: all)

  ## Examples

      Choreo.Dependency.Analysis.centrality(deps)
      #=> [:util, :auth, :api]
  """
  @spec centrality(Dependency.t(), keyword()) :: [Yog.node_id()]
  def centrality(%Dependency{graph: graph}, opts \\ []) do
    limit = Keyword.get(opts, :limit, nil)

    ranked =
      graph.nodes
      |> Enum.map(fn {id, _data} ->
        in_deg = Yog.in_degree(graph, id)
        out_deg = Yog.out_degree(graph, id)
        {id, in_deg + out_deg}
      end)
      |> Enum.sort_by(fn {_id, score} -> -score end)
      |> Enum.map(fn {id, _score} -> id end)

    if limit, do: Enum.take(ranked, limit), else: ranked
  end

  @doc """
  Returns nodes with no dependents (nothing depends on them).

  These are safe to change or delete without breaking other components.
  """
  @spec leaves(Dependency.t()) :: [Yog.node_id()]
  def leaves(%Dependency{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {id, _data} -> Yog.in_degree(graph, id) == 0 end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns nodes with no dependencies (foundational components).

  These are the bottom of the dependency stack.
  """
  @spec roots(Dependency.t()) :: [Yog.node_id()]
  def roots(%Dependency{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {id, _data} -> Yog.out_degree(graph, id) == 0 end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Finds the longest dependency chain in the graph.

  This measures the maximum depth of the dependency tree — useful for
  estimating compilation or test ordering time.

  Returns `{:ok, [id], total_weight}` or `:error` if cyclic.

  ## Examples

      deps =
        Choreo.Dependency.new()
        |> Choreo.Dependency.add_module(:a)
        |> Choreo.Dependency.add_module(:b)
        |> Choreo.Dependency.add_module(:c)
        |> Choreo.Dependency.depends_on(:a, :b)
        |> Choreo.Dependency.depends_on(:b, :c)

      Choreo.Dependency.Analysis.longest_dependency_chain(deps)
      #=> {:ok, [:a, :b, :c], 2}
  """
  @spec longest_dependency_chain(Dependency.t()) :: {:ok, [Yog.node_id()], number()} | :error
  def longest_dependency_chain(%Dependency{graph: graph}) do
    if Yog.cyclic?(graph) do
      :error
    else
      case Yog.Traversal.Sort.topological_sort(graph) do
        {:ok, order} ->
          dp = Choreo.Internal.compute_dp(graph, order)

          case Choreo.Internal.find_best_end_path(dp) do
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
  Validates a dependency graph and returns a list of issues.

  Checks for:
    * circular dependencies
    * orphaned nodes (no edges at all)

  Returns a list of `{severity, message}` tuples.
  """
  @spec validate(Dependency.t()) :: [{:error | :warning, String.t()}]
  def validate(%Dependency{} = deps) do
    []
    |> check_cycles(deps)
    |> check_orphans(deps)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp find_cycle(_graph, _start, _current, _visited, path) when length(path) > 50 do
    # Safety guard against runaway DFS
    nil
  end

  defp find_cycle(graph, start, current, visited, path) do
    successors =
      graph
      |> Yog.successor_ids(current)
      |> Enum.filter(&MapSet.member?(visited, &1))

    if start in successors do
      Enum.reverse([start | path])
    else
      # Explore unvisited successors within the SCC
      unvisited =
        graph
        |> Yog.successor_ids(current)
        |> Enum.reject(&MapSet.member?(visited, &1))

      Enum.find_value(unvisited, fn next ->
        find_cycle(graph, start, next, MapSet.put(visited, next), [next | path])
      end)
    end
  end

  defp check_cycles(acc, deps) do
    case cyclic_dependencies(deps) do
      [] ->
        acc

      cycles ->
        cycle_str =
          cycles
          |> Enum.map_join(", ", fn path -> "#{inspect(path)}" end)

        [{:error, "Circular dependencies: #{cycle_str}"} | acc]
    end
  end

  defp check_orphans(acc, deps) do
    isolated =
      Dependency.nodes(deps)
      |> Enum.filter(fn id ->
        Yog.in_degree(deps.graph, id) == 0 and Yog.out_degree(deps.graph, id) == 0
      end)

    if isolated == [] do
      acc
    else
      [{:warning, "Isolated nodes: #{inspect(isolated)}"} | acc]
    end
  end
end
