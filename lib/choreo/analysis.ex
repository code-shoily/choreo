defmodule Choreo.Analysis do
  @moduledoc """
  Graph-algorithm wrappers for `Choreo` architecture diagrams.

  These functions adapt the generic algorithms from `Yog` to the
  domain of system architecture.

  ## Semiring support

  Functions that deal with path weights (e.g. `shortest_path/4`,
  `mst/2`) accept semiring options so you can define "shortest" in
  terms of **cost**, **latency**, or any custom metric:

      # Shortest by cost (default — numeric addition)
      Choreo.Analysis.shortest_path(system, :api, :db)

      # Shortest by latency stored in edge meta
      Choreo.Analysis.shortest_path(system, :api, :db,
        zero: 0,
        add: &Kernel.+/2,
        compare: &Yog.Utils.compare/2
      )

  ## Domain-specific analysis

    * `single_points_of_failure/1` — articulation points and bridge edges
    * `impact_analysis/2` — what breaks if a node goes down
    * `centrality/2` — most coupled / critical services
    * `isolated_nodes/1` — orphan services with no connections
    * `validate/1` — structural health check
  """

  alias Choreo

  # ============================================================================
  # Existing algorithms
  # ============================================================================

  @doc """
    Computes a Minimum Spanning Tree (MST) of the system.

    The MST is calculated on an **undirected** copy of the graph using
    Kruskal's algorithm. Edge costs are the weights given to `connect/4`.

    Returns `{:ok, Yog.MST.Result.t()}` or `{:error, reason}`.

    ## Options

      * `:algorithm` - `:kruskal` (default), `:prim`, `:boruvka`
      * `:compare` - custom comparison function for edge weights

    ## Examples

        system =
          Choreo.new(directed: false)
          |> Choreo.add_database(:db)
          |> Choreo.add_service(:api)
          |> Choreo.add_cache(:cache)
          |> Choreo.connect(:api, :db, cost: 10)
          |> Choreo.connect(:api, :cache, cost: 5)
          |> Choreo.connect(:db, :cache, cost: 20)

        {:ok, mst} = Choreo.Analysis.mst(system)

    This analysis answers the question: "What is the cheapest way to connect all services?"
  """
  @spec mst(Choreo.t(), keyword()) ::
          {:ok, Yog.MST.Result.t()} | {:error, atom() | String.t()}
  def mst(%Choreo{graph: graph}, opts \\ []) do
    algorithm = Keyword.get(opts, :algorithm, :kruskal)

    # Ensure we work on an undirected graph
    graph =
      if graph.kind == :directed do
        Yog.Transform.to_undirected(graph, &min/2)
      else
        graph
      end

    case algorithm do
      :kruskal -> Yog.MST.kruskal(graph, opts[:compare] || (&Yog.Utils.compare/2))
      :prim -> Yog.MST.prim(graph)
      :boruvka -> Yog.MST.boruvka(graph)
      _ -> {:error, "Unknown algorithm: #{algorithm}"}
    end
  end

  @doc """
    Returns a topological ordering of the system nodes.

    This is useful for determining execution order in data-flow
    pipelines. The system graph must be a DAG; if cycles exist,
    `{:error, reason}` is returned.

    ## Examples

        system =
          Choreo.new()
          |> Choreo.add_service(:ingest)
          |> Choreo.add_service(:transform)
          |> Choreo.add_service(:store)
          |> Choreo.add_dataflow(:ingest, :transform)
          |> Choreo.add_dataflow(:transform, :store)

        {:ok, order} = Choreo.Analysis.topological_sort(system)
        # order => [:ingest, :transform, :store]

    This analysis answers the question: "In what order should I deploy or initialise services?"
  """
  @spec topological_sort(Choreo.t()) :: {:ok, [Yog.node_id()]} | {:error, String.t()}
  def topological_sort(%Choreo{graph: graph}) do
    case Yog.Traversal.Sort.topological_sort(graph) do
      {:ok, order} -> {:ok, order}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
    Detects cycles in the system.

    Returns `true` if the system contains at least one cycle.
    This analysis answers the question: "Does my architecture contain a feedback loop?"
  """
  @spec cyclic?(Choreo.t()) :: boolean()
  def cyclic?(%Choreo{graph: graph}) do
    Yog.cyclic?(graph)
  end

  @doc """
    Returns `true` if the system is a Directed Acyclic Graph (DAG).
    This analysis answers the question: "Can I safely order my services linearly?"
  """
  @spec dag?(Choreo.t()) :: boolean()
  def dag?(%Choreo{graph: graph}) do
    Yog.acyclic?(graph)
  end

  @doc """
    Returns the strongly-connected components of the system.

    Each component is a list of node IDs that are mutually reachable.
    Single-node components indicate nodes that are not part of a cycle.

    ## Examples

        components = Choreo.Analysis.strongly_connected_components(system)

    This analysis answers the question: "Which services are mutually dependent?"
  """
  @spec strongly_connected_components(Choreo.t()) :: [[Yog.node_id()]]
  def strongly_connected_components(%Choreo{graph: graph}) do
    Yog.Connectivity.strongly_connected_components(graph)
  end

  # ============================================================================
  # Single points of failure
  # ============================================================================

  @doc """
    Identifies single points of failure in the architecture.

    Returns a map with:

      * `:nodes` — articulation points: services whose removal would
        partition the system into disconnected components
      * `:edges` — bridge edges: connections whose removal would split
        the system

    Uses Tarjan's algorithm on an undirected view of the graph.

    ## Examples

        system =
          Choreo.new()
          |> Choreo.add_service(:api)
          |> Choreo.add_service(:auth)
          |> Choreo.add_database(:db)
          |> Choreo.connect(:api, :auth)
          |> Choreo.connect(:auth, :db)

        result = Choreo.Analysis.single_points_of_failure(system)
        result.nodes  #=> [:auth]
        result.edges  #=> [{:api, :auth}, {:auth, :db}]

    This analysis answers the question: "Which services or links would take down the whole system if they failed?"
  """
  @spec single_points_of_failure(Choreo.t()) :: %{
          nodes: [Yog.node_id()],
          edges: [{Yog.node_id(), Yog.node_id()}]
        }
  def single_points_of_failure(%Choreo{graph: graph}) do
    undirected = ensure_undirected(graph)
    result = Yog.Connectivity.analyze(undirected)

    %{
      nodes: result.articulation_points,
      edges: result.bridges
    }
  end

  # ============================================================================
  # Impact analysis
  # ============================================================================

  @doc """
    Returns all nodes that are transitively affected if `target` goes down.

    Uses BFS on the transposed graph: if A → B → C and `target` is B,
    then A depends (transitively) on B, so A is affected.

    ## Examples

        system =
          Choreo.new()
          |> Choreo.add_service(:api)
          |> Choreo.add_service(:auth)
          |> Choreo.add_database(:db)
          |> Choreo.connect(:api, :auth)
          |> Choreo.connect(:auth, :db)

        Choreo.Analysis.impact_analysis(system, :db)
        #=> [:auth, :api]

    This analysis answers the question: "What breaks if this service goes down?"
  """
  @spec impact_analysis(Choreo.t(), Yog.node_id()) :: [Yog.node_id()]
  def impact_analysis(%Choreo{graph: graph}, target) do
    transposed = Yog.transpose(graph)

    Choreo.Internal.bfs_reachable(transposed, [target])
    |> MapSet.to_list()
    |> List.delete(target)
  end

  # ============================================================================
  # Shortest path
  # ============================================================================

  @doc """
    Finds the shortest (cheapest) path between two services.

    Supports semiring-parameterised weights: pass `:zero`, `:add`, and
    `:compare` to define "shortest" in terms of cost, latency, or any
    custom metric.

    Returns `{:ok, path}` where `path` has `.nodes` and `.weight`,
    or `:error` if no path exists.

    ## Options

      * `:zero` — identity element for the weight type (default: `0`)
      * `:add` — function to combine two weights (default: `&Kernel.+/2`)
      * `:compare` — function returning `:lt`, `:eq`, `:gt` (default: `&Yog.Utils.compare/2`)

    ## Examples

        # Shortest by cost (default)
        {:ok, path} = Choreo.Analysis.shortest_path(system, :api, :db)
        path.nodes   #=> [:api, :auth, :db]
        path.weight  #=> 15

    This analysis answers the question: "What is the fastest or cheapest route between two services?"
  """
  @spec shortest_path(Choreo.t(), Yog.node_id(), Yog.node_id(), keyword()) ::
          {:ok, map()} | :error
  def shortest_path(%Choreo{graph: graph}, from, to, opts \\ []) do
    zero = Keyword.get(opts, :zero, 0)
    add = Keyword.get(opts, :add, &Kernel.+/2)
    compare = Keyword.get(opts, :compare, &Yog.Utils.compare/2)

    Yog.Pathfinding.Dijkstra.shortest_path(graph, from, to, zero, add, compare)
  end

  # ============================================================================
  # Centrality
  # ============================================================================

  @doc """
    Ranks nodes by centrality — identifying the most critical services.

    ## Options

      * `:measure` — centrality algorithm to use:
        - `:degree` (default) — simple connectivity count
        - `:betweenness` — bridge/gatekeeper detection
        - `:closeness` — distance-based importance
        - `:pagerank` — link-quality importance (directed graphs)
      * `:limit` — return only the top N results
      * `:mode` — for degree centrality: `:in_degree`, `:out_degree`,
        or `:total_degree` (default)
      * Semiring options (`:zero`, `:add`, `:compare`, `:to_float`)
        for betweenness and closeness

    Returns a list of `{node_id, score}` tuples sorted by score descending.

    ## Examples

        # Most connected services
        Choreo.Analysis.centrality(system)
        #=> [{:api, 1.0}, {:auth, 0.67}, {:db, 0.33}]

        # Top 3 bottleneck/bridge services
        Choreo.Analysis.centrality(system, measure: :betweenness, limit: 3)

    This analysis answers the question: "Which services are the most critical connectors?"
  """
  @spec centrality(Choreo.t(), keyword()) :: [{Yog.node_id(), float()}]
  def centrality(%Choreo{graph: graph}, opts \\ []) do
    measure = Keyword.get(opts, :measure, :degree)
    limit = Keyword.get(opts, :limit, nil)

    scores =
      case measure do
        :degree ->
          mode = Keyword.get(opts, :mode, :total_degree)
          Yog.Centrality.degree(graph, mode)

        :betweenness ->
          semiring_opts = Keyword.take(opts, [:zero, :add, :compare, :to_float])
          Yog.Centrality.betweenness(graph, semiring_opts)

        :closeness ->
          semiring_opts = Keyword.take(opts, [:zero, :add, :compare, :to_float])
          Yog.Centrality.closeness(graph, semiring_opts)

        :pagerank ->
          pagerank_opts = Keyword.take(opts, [:damping, :max_iterations, :tolerance])
          Yog.Centrality.pagerank(graph, pagerank_opts)
      end

    ranked =
      scores
      |> Enum.sort_by(fn {_id, score} -> -score end)

    if limit, do: Enum.take(ranked, limit), else: ranked
  end

  # ============================================================================
  # Isolated nodes
  # ============================================================================

  @doc """
    Returns nodes with no connections (zero in-degree and out-degree).

    Isolated services in an architecture diagram are usually a mistake —
    either a missing connection or an orphaned component.

    ## Examples

        Choreo.Analysis.isolated_nodes(system)
        #=> [:orphan_service]

    This analysis answers the question: "Which services have no connections at all?"
  """
  @spec isolated_nodes(Choreo.t()) :: [Yog.node_id()]
  def isolated_nodes(%Choreo{graph: graph}) do
    graph.nodes
    |> Map.keys()
    |> Enum.filter(fn id ->
      Yog.in_degree(graph, id) == 0 and Yog.out_degree(graph, id) == 0
    end)
  end

  # ============================================================================
  # Validation
  # ============================================================================

  @doc """
    Validates the system architecture and returns a list of issues.

    Checks for:

      * isolated nodes (no connections)
      * single points of failure (articulation points)
      * cycles in a directed system
      * bridge edges (single connection between components)

    Returns a list of `{severity, message}` tuples.

    ## Examples

        Choreo.Analysis.validate(system)
        #=> [
        #=>   {:warning, "Isolated nodes: [:orphan]"},
        #=>   {:warning, "Single points of failure: [:auth]"},
        #=>   {:warning, "Bridge edges: [{:auth, :db}]"}
        #=> ]

    This analysis answers the question: "Is my architecture structurally sound?"
  """
  @spec validate(Choreo.t()) :: [{:error | :warning, String.t()}]
  def validate(%Choreo{} = system) do
    []
    |> check_isolated(system)
    |> check_spof(system)
    |> check_cycles(system)
    |> check_bridges(system)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp ensure_undirected(graph) do
    if graph.kind == :directed do
      Yog.Transform.to_undirected(graph, &min/2)
    else
      graph
    end
  end

  defp check_isolated(acc, system) do
    case isolated_nodes(system) do
      [] -> acc
      nodes -> [{:warning, "Isolated nodes: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_spof(acc, system) do
    %{nodes: spof_nodes} = single_points_of_failure(system)

    case spof_nodes do
      [] -> acc
      nodes -> [{:warning, "Single points of failure: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_cycles(acc, %Choreo{graph: graph} = _system) do
    if graph.kind == :directed and Yog.cyclic?(graph) do
      [{:error, "Cycle detected in system"} | acc]
    else
      acc
    end
  end

  defp check_bridges(acc, system) do
    %{edges: bridges} = single_points_of_failure(system)

    case bridges do
      [] -> acc
      edges -> [{:warning, "Bridge edges: #{inspect(edges)}"} | acc]
    end
  end
end
