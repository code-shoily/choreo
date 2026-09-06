defmodule Choreo.Dependency.Analysis do
  @moduledoc """
  Analysis functions for `Choreo.Dependency` graphs.

  Provides algorithms that answer practical questions about a codebase:

    * Where are the circular dependencies?
    * What breaks if I change a component?
    * Are we violating our layer architecture?
    * Which components are most coupled?
    * What is the deepest dependency chain?

  ## Further reading

    * [Dependency inversion principle](https://en.wikipedia.org/wiki/Dependency_inversion_principle)
    * [Circular dependency](https://en.wikipedia.org/wiki/Circular_dependency)
    * [Software architecture](https://en.wikipedia.org/wiki/Software_architecture)
  """

  alias Choreo.Dependency

  @doc """
  Returns all circular dependency chains.

  Each cycle is returned as a list of node IDs starting and ending at the
  same node. Only one representative cycle is returned per strongly
  connected component.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.add_module(:c)
      ...>   |> Choreo.Dependency.depends_on(:a, :b)
      ...>   |> Choreo.Dependency.depends_on(:b, :a)
      ...>   |> Choreo.Dependency.depends_on(:c, :a)
      iex> cycles = Choreo.Dependency.Analysis.cyclic_dependencies(deps)
      iex> length(cycles)
      1
      iex> [cycle] = cycles
      iex> hd(cycle) == List.last(cycle)
      true
      iex> :a in cycle
      true
      iex> :b in cycle
      true

  This analysis answers the question: "Where are the circular dependencies?"
  """
  @spec cyclic_dependencies(Dependency.t()) :: [[Yog.node_id()]]
  def cyclic_dependencies(%Dependency{} = deps) do
    simple_graph = Dependency.to_simple_graph(deps)
    sccs = Yog.Connectivity.scc(simple_graph)

    sccs
    |> Enum.filter(fn component -> length(component) > 1 end)
    |> Enum.map(fn component ->
      # Pick a canonical start node so cycle order is deterministic
      start = component |> Enum.sort() |> hd()
      find_cycle(simple_graph, start, start, MapSet.new([start]), [start])
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Checks whether the dependency graph contains any circular dependencies.

  ## Examples

      iex> deps =
      ...>   Choreo.Dependency.new()
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.depends_on(:a, :b)
      iex> Choreo.Dependency.Analysis.cyclic?(deps)
      false
      iex> cyclic_deps = Choreo.Dependency.depends_on(deps, :b, :a)
      iex> Choreo.Dependency.Analysis.cyclic?(cyclic_deps)
      true

  This analysis answers the question: "Are there any circular dependencies?"
  """
  @spec cyclic?(Dependency.t()) :: boolean()
  def cyclic?(%Dependency{} = deps) do
    deps
    |> Dependency.to_simple_graph()
    |> Yog.cyclic?()
  end

  @doc """
  Returns all nodes that transitively depend on the given node.

  If you change `target`, these are the components that could break.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api)
      ...>   |> Choreo.Dependency.add_module(:auth)
      ...>   |> Choreo.Dependency.add_module(:util)
      ...>   |> Choreo.Dependency.depends_on(:api, :auth)
      ...>   |> Choreo.Dependency.depends_on(:auth, :util)
      iex> Enum.sort(Choreo.Dependency.Analysis.affected_by(deps, :util))
      [:api, :auth]
      iex> Choreo.Dependency.Analysis.affected_by(deps, :api)
      []

  This analysis answers the question: "What breaks if I change this component?"
  """
  @spec affected_by(Dependency.t(), Yog.node_id()) :: [Yog.node_id()]
  def affected_by(%Dependency{} = deps, target) do
    simple_graph = Dependency.to_simple_graph(deps)
    transposed = Yog.transpose(simple_graph)

    Choreo.Internal.bfs_reachable(transposed, [target])
    |> MapSet.to_list()
    |> List.delete(target)
    |> Enum.sort()
  end

  @doc """
  Returns all nodes that the given node transitively depends on.

  These are the components `target` cannot function without.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api)
      ...>   |> Choreo.Dependency.add_module(:auth)
      ...>   |> Choreo.Dependency.add_module(:util)
      ...>   |> Choreo.Dependency.depends_on(:api, :auth)
      ...>   |> Choreo.Dependency.depends_on(:auth, :util)
      iex> Enum.sort(Choreo.Dependency.Analysis.depends_on(deps, :api))
      [:auth, :util]
      iex> Choreo.Dependency.Analysis.depends_on(deps, :util)
      []

  This analysis answers the question: "What does this component need to function?"
  """
  @spec depends_on(Dependency.t(), Yog.node_id()) :: [Yog.node_id()]
  def depends_on(%Dependency{} = deps, target) do
    simple_graph = Dependency.to_simple_graph(deps)

    Choreo.Internal.bfs_reachable(simple_graph, [target])
    |> MapSet.to_list()
    |> List.delete(target)
    |> Enum.sort()
  end

  @doc """
  Returns the components that the given node directly depends on.

  Only immediate outgoing dependencies are returned. For transitive
  dependencies, see `depends_on/2`.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api)
      ...>   |> Choreo.Dependency.add_module(:auth)
      ...>   |> Choreo.Dependency.add_module(:util)
      ...>   |> Choreo.Dependency.depends_on(:api, :auth)
      ...>   |> Choreo.Dependency.depends_on(:auth, :util)
      iex> Choreo.Dependency.Analysis.direct_dependencies(deps, :api)
      [:auth]
      iex> Choreo.Dependency.Analysis.direct_dependencies(deps, :util)
      []

  This analysis answers the question: "Which components does this node directly depend on?"
  """
  @spec direct_dependencies(Dependency.t(), Yog.node_id()) :: [Yog.node_id()]
  def direct_dependencies(%Dependency{} = deps, target) do
    simple_graph = Dependency.to_simple_graph(deps)

    if Map.has_key?(simple_graph.nodes, target) do
      Yog.successor_ids(simple_graph, target) |> Enum.sort()
    else
      []
    end
  end

  @doc """
  Returns the components that directly depend on the given node.

  Only immediate incoming dependents are returned. For transitive
  dependents (blast radius), see `affected_by/2`.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api)
      ...>   |> Choreo.Dependency.add_module(:auth)
      ...>   |> Choreo.Dependency.add_module(:util)
      ...>   |> Choreo.Dependency.depends_on(:api, :auth)
      ...>   |> Choreo.Dependency.depends_on(:auth, :util)
      iex> Choreo.Dependency.Analysis.direct_dependents(deps, :auth)
      [:api]
      iex> Choreo.Dependency.Analysis.direct_dependents(deps, :api)
      []

  This analysis answers the question: "Which components directly depend on this node?"
  """
  @spec direct_dependents(Dependency.t(), Yog.node_id()) :: [Yog.node_id()]
  def direct_dependents(%Dependency{} = deps, target) do
    simple_graph = Dependency.to_simple_graph(deps)

    if Map.has_key?(simple_graph.nodes, target) do
      Yog.predecessors(simple_graph, target)
      |> Enum.map(fn {pred, _w} -> pred end)
      |> Enum.sort()
    else
      []
    end
  end

  @doc """
  Checks edges against an expected layered architecture.

  `layers` is a map of `node_id => layer_index` where lower numbers are
  "lower" layers (foundations). A violation occurs when an edge points
  from a lower layer to a higher layer (the dependency arrow goes
  upward).

  Returns a list of violation tuples: `{from, to, description}`.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:repo)
      ...>   |> Choreo.Dependency.add_module(:service)
      ...>   |> Choreo.Dependency.add_module(:api)
      ...>   |> Choreo.Dependency.depends_on(:service, :repo)
      ...>   |> Choreo.Dependency.depends_on(:repo, :api)
      iex> layers = %{repo: 1, service: 2, api: 3}
      iex> violations = Choreo.Dependency.Analysis.layer_violations(deps, layers)
      iex> length(violations)
      1
      iex> {from, to, _desc} = hd(violations)
      iex> from
      :repo
      iex> to
      :api

  This analysis answers the question: "Which edges violate my layered architecture?"
  """
  @spec layer_violations(Dependency.t(), %{Yog.node_id() => integer()}) :: [
          {Yog.node_id(), Yog.node_id(), String.t()}
        ]
  def layer_violations(%Dependency{} = deps, layers) do
    simple_graph = Dependency.to_simple_graph(deps)

    simple_graph
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

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:hub)
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.add_module(:c)
      ...>   |> Choreo.Dependency.depends_on(:a, :hub)
      ...>   |> Choreo.Dependency.depends_on(:b, :hub)
      ...>   |> Choreo.Dependency.depends_on(:hub, :c)
      iex> hd(Choreo.Dependency.Analysis.centrality(deps))
      :hub
      iex> length(Choreo.Dependency.Analysis.centrality(deps, limit: 2))
      2

  This analysis answers the question: "Which components are the most coupled?"
  """
  @spec centrality(Dependency.t(), keyword()) :: [Yog.node_id()]
  def centrality(%Dependency{} = deps, opts \\ []) do
    limit = Keyword.get(opts, :limit, nil)
    simple_graph = Dependency.to_simple_graph(deps)

    ranked =
      simple_graph.nodes
      |> Enum.map(fn {id, _data} ->
        in_deg = Yog.in_degree(simple_graph, id)
        out_deg = Yog.out_degree(simple_graph, id)
        {id, in_deg + out_deg}
      end)
      |> Enum.sort_by(fn {_id, score} -> -score end)
      |> Enum.map(fn {id, _score} -> id end)

    if limit, do: Enum.take(ranked, limit), else: ranked
  end

  @doc """
  Returns nodes with no dependents (nothing depends on them).

  These are "source" nodes in the dependency graph — safe to change or
  delete without breaking other components.

  > ### Naming note
  > In dependency-graph terminology a *leaf* is a node at the top of the
  > stack (nothing depends on it). This is the inverse of tree terminology
  > where a leaf is at the bottom.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.add_module(:c)
      ...>   |> Choreo.Dependency.depends_on(:a, :b)
      ...>   |> Choreo.Dependency.depends_on(:b, :c)
      iex> Choreo.Dependency.Analysis.leaves(deps)
      [:a]

  This analysis answers the question: "Which components have no dependents?"
  """
  @spec leaves(Dependency.t()) :: [Yog.node_id()]
  def leaves(%Dependency{} = deps) do
    simple_graph = Dependency.to_simple_graph(deps)

    simple_graph.nodes
    |> Enum.filter(fn {id, _data} -> Yog.in_degree(simple_graph, id) == 0 end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns nodes with no dependencies (foundational components).

  These are the bottom of the dependency stack — nodes that nothing else
  depends on and that have no outgoing edges.

  > ### Naming note
  > In dependency-graph terminology a *root* is a node at the bottom of the
  > stack (depends on nothing). This is the inverse of tree terminology
  > where a root is at the top.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.add_module(:c)
      ...>   |> Choreo.Dependency.depends_on(:a, :b)
      ...>   |> Choreo.Dependency.depends_on(:b, :c)
      iex> Choreo.Dependency.Analysis.roots(deps)
      [:c]

  This analysis answers the question: "Which components have no dependencies?"
  """
  @spec roots(Dependency.t()) :: [Yog.node_id()]
  def roots(%Dependency{} = deps) do
    simple_graph = Dependency.to_simple_graph(deps)

    simple_graph.nodes
    |> Enum.filter(fn {id, _data} -> Yog.out_degree(simple_graph, id) == 0 end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Identifies redundant explicit dependencies.

  If A depends on B, B depends on C, and A depends on C, the direct
  edge A -> C is often redundant. This returns a list of `{from, to}`
  tuples representing these redundant edges.

  > ### Limitation
  > This algorithm assumes a directed acyclic graph. On cyclic graphs it
  > returns an empty list because every edge in a strongly connected
  > component is part of a cycle and therefore not transitively redundant.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.add_module(:c)
      ...>   |> Choreo.Dependency.depends_on(:a, :b)
      ...>   |> Choreo.Dependency.depends_on(:b, :c)
      ...>   |> Choreo.Dependency.depends_on(:a, :c)
      iex> Choreo.Dependency.Analysis.transitive_reduction(deps)
      [{:a, :c}]

  This analysis answers the question: "Which explicit dependencies are redundant?"
  """
  @spec transitive_reduction(Dependency.t()) :: [{Yog.node_id(), Yog.node_id()}]
  def transitive_reduction(%Dependency{} = deps) do
    deps
    |> Dependency.to_simple_graph()
    |> Choreo.Internal.transitive_reduction()
  end

  @doc """
  Calculates the Instability metric for each component.

  Formula: `Efferent Coupling / (Afferent + Efferent Coupling)`
  Returns a map of `node_id => instability_score`.
  A score of 0.0 means the component is maximally stable.
  A score of 1.0 means the component is maximally unstable.

  > ### Note on parallel edges
  > This analysis collapses parallel edges into a single edge before
  > computing degrees, so multiple edges of different types between the
  > same pair of nodes count as one dependency.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:stable)
      ...>   |> Choreo.Dependency.add_module(:unstable)
      ...>   |> Choreo.Dependency.add_module(:mixed)
      ...>   |> Choreo.Dependency.depends_on(:unstable, :stable)
      ...>   |> Choreo.Dependency.depends_on(:unstable, :mixed)
      ...>   |> Choreo.Dependency.depends_on(:mixed, :stable)
      iex> scores = Choreo.Dependency.Analysis.instability(deps)
      iex> scores.stable
      0.0
      iex> scores.unstable
      1.0
      iex> scores.mixed
      0.5

  This analysis answers the question: "How stable is each component?"
  """
  @spec instability(Dependency.t()) :: %{Yog.node_id() => float()}
  def instability(%Dependency{} = deps) do
    simple_graph = Dependency.to_simple_graph(deps)

    simple_graph.nodes
    |> Enum.map(fn {id, _data} ->
      ce = Yog.out_degree(simple_graph, id)
      ca = Yog.in_degree(simple_graph, id)

      score =
        if ca + ce == 0 do
          0.0
        else
          ce / (ca + ce)
        end

      {id, score}
    end)
    |> Map.new()
  end

  @doc """
  Identifies completely isolated subsystems (weakly connected components).

  Returns a list of components, where each component is a list of node IDs.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:a1)
      ...>   |> Choreo.Dependency.add_module(:a2)
      ...>   |> Choreo.Dependency.depends_on(:a1, :a2)
      ...>   |> Choreo.Dependency.add_module(:b1)
      ...>   |> Choreo.Dependency.add_module(:b2)
      ...>   |> Choreo.Dependency.depends_on(:b1, :b2)
      ...>   |> Choreo.Dependency.add_module(:orphan)
      iex> subsystems = Choreo.Dependency.Analysis.isolated_subsystems(deps)
      iex> length(subsystems)
      3
      iex> Enum.any?(subsystems, fn g -> Enum.sort(g) == [:a1, :a2] end)
      true
      iex> Enum.any?(subsystems, fn g -> g == [:orphan] end)
      true

  This analysis answers the question: "Which groups of components are completely disconnected?"
  """
  @spec isolated_subsystems(Dependency.t()) :: [[Yog.node_id()]]
  def isolated_subsystems(%Dependency{} = deps) do
    simple_graph = Dependency.to_simple_graph(deps)
    Yog.Connectivity.weakly_connected_components(simple_graph)
  end

  @doc """
  Returns all disconnected nodes with no incoming or outgoing dependencies.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.add_module(:orphan)
      ...>   |> Choreo.Dependency.depends_on(:a, :b)
      iex> Choreo.Dependency.Analysis.isolated_nodes(deps)
      [:orphan]

  This analysis answers the question: "Which components are completely isolated?"
  """
  @spec isolated_nodes(Dependency.t()) :: [Yog.node_id()]
  def isolated_nodes(%Dependency{} = deps) do
    simple_graph = Dependency.to_simple_graph(deps)

    Dependency.nodes(deps)
    |> Enum.filter(fn id ->
      Yog.in_degree(simple_graph, id) == 0 and Yog.out_degree(simple_graph, id) == 0
    end)
    |> Enum.sort()
  end

  @doc """
  Finds the longest dependency chain in the graph.

  This measures the maximum depth of the dependency tree — useful for
  estimating compilation or test ordering time.

  Returns `{:ok, [id], total_weight}` or `:error` if cyclic.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.add_module(:c)
      ...>   |> Choreo.Dependency.depends_on(:a, :b)
      ...>   |> Choreo.Dependency.depends_on(:b, :c)
      iex> Choreo.Dependency.Analysis.longest_dependency_chain(deps)
      {:ok, [:a, :b, :c], 2}

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.depends_on(:a, :b)
      ...>   |> Choreo.Dependency.depends_on(:b, :a)
      iex> Choreo.Dependency.Analysis.longest_dependency_chain(deps)
      :error

  This analysis answers the question: "What is the deepest dependency chain?"
  """
  @spec longest_dependency_chain(Dependency.t()) :: {:ok, [Yog.node_id()], number()} | :error
  def longest_dependency_chain(%Dependency{} = deps) do
    simple_graph = Dependency.to_simple_graph(deps)

    if Yog.cyclic?(simple_graph) do
      :error
    else
      case Yog.Traversal.Sort.topological_sort(simple_graph) do
        {:ok, order} ->
          dp = Choreo.Internal.compute_dp(simple_graph, order)

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
  Computes a topological sort of the dependency graph in dependency order.

  Returns `{:ok, [node_id]}` where upstream dependents come before downstream
  dependencies, or `{:error, :contains_cycle}` if the graph is cyclic.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:app)
      ...>   |> Choreo.Dependency.add_module(:core)
      ...>   |> Choreo.Dependency.depends_on(:app, :core)
      iex> {:ok, order} = Choreo.Dependency.Analysis.topological_sort(deps)
      iex> order
      [:app, :core]

  This analysis answers the question: "What is a valid topological ordering of the components?"
  """
  @spec topological_sort(Dependency.t()) :: {:ok, [Yog.node_id()]} | {:error, :contains_cycle}
  def topological_sort(%Dependency{} = deps) do
    deps
    |> Dependency.to_simple_graph()
    |> Yog.Traversal.Sort.topological_sort()
  end

  @doc """
  Computes a safe compilation, build, or boot sequence.

  Components with no dependencies appear first, followed by components that
  depend only on previously built components.

  Returns `{:ok, [node_id]}` or `{:error, :contains_cycle}`.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api)
      ...>   |> Choreo.Dependency.add_module(:service)
      ...>   |> Choreo.Dependency.add_module(:repo)
      ...>   |> Choreo.Dependency.depends_on(:api, :service)
      ...>   |> Choreo.Dependency.depends_on(:service, :repo)
      iex> {:ok, order} = Choreo.Dependency.Analysis.build_order(deps)
      iex> order
      [:repo, :service, :api]

  This analysis answers the question: "In what order should components be built or initialized?"
  """
  @spec build_order(Dependency.t()) :: {:ok, [Yog.node_id()]} | {:error, :contains_cycle}
  def build_order(%Dependency{} = deps) do
    case topological_sort(deps) do
      {:ok, order} -> {:ok, Enum.reverse(order)}
      error -> error
    end
  end

  @doc """
  Validates a dependency graph and returns a list of issues.

  Checks for:
    * circular dependencies
    * orphaned nodes (no edges at all)

  Layer violations are *not* checked by `validate/1`; use
  `layer_violations/2` with an explicit layer map for that.

  Returns a list of `{severity, message}` tuples.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.depends_on(:a, :b)
      iex> Choreo.Dependency.Analysis.validate(deps)
      []

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_module(:a)
      ...>   |> Choreo.Dependency.add_module(:b)
      ...>   |> Choreo.Dependency.depends_on(:a, :b)
      ...>   |> Choreo.Dependency.depends_on(:b, :a)
      iex> issues = Choreo.Dependency.Analysis.validate(deps)
      iex> Enum.any?(issues, fn {sev, msg} -> sev == :error and String.contains?(msg, "Circular") end)
      true

  This analysis answers the question: "Is the dependency graph structurally sound?"
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
    case isolated_nodes(deps) do
      [] ->
        acc

      isolated ->
        [{:warning, "Isolated nodes: #{inspect(isolated)}"} | acc]
    end
  end
end
