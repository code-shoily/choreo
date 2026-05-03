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

        iex> system =
        ...>   Choreo.new(directed: false)
        ...>   |> Choreo.add_database(:db)
        ...>   |> Choreo.add_service(:api)
        ...>   |> Choreo.add_cache(:cache)
        ...>   |> Choreo.connect(:api, :db, cost: 10)
        ...>   |> Choreo.connect(:api, :cache, cost: 5)
        ...>   |> Choreo.connect(:db, :cache, cost: 20)
        iex> {:ok, mst} = Choreo.Analysis.mst(system)
        iex> mst.total_weight
        15

    This analysis answers the question: "What is the cheapest way to connect all services?"
  """
  @spec mst(Choreo.t(), keyword()) ::
          {:ok, Yog.MST.Result.t()} | {:error, atom() | String.t()}
  def mst(%Choreo{} = system, opts \\ []) do
    algorithm = Keyword.get(opts, :algorithm, :kruskal)

    # Collapse parallel edges and ensure we work on an undirected graph
    graph = Choreo.to_simple_graph(system)

    graph =
      if graph.kind == :directed do
        Yog.Transform.to_undirected(graph, &min/2)
      else
        graph
      end

    case algorithm do
      :kruskal -> Yog.MST.kruskal(graph, opts[:compare] || (&Yog.Utils.compare/2))
      :prim -> Yog.MST.prim(graph, opts[:compare] || (&Yog.Utils.compare/2))
      :boruvka -> Yog.MST.boruvka(graph, opts[:compare] || (&Yog.Utils.compare/2))
      _ -> {:error, "Unknown algorithm: #{algorithm}"}
    end
  end

  @doc """
    Returns a topological ordering of the system nodes.

    This is useful for determining execution order in data-flow
    pipelines. The system graph must be a DAG; if cycles exist,
    `{:error, reason}` is returned.

    ## Examples

        iex> system =
        ...>   Choreo.new()
        ...>   |> Choreo.add_service(:ingest)
        ...>   |> Choreo.add_service(:transform)
        ...>   |> Choreo.add_service(:store)
        ...>   |> Choreo.add_dataflow(:ingest, :transform)
        ...>   |> Choreo.add_dataflow(:transform, :store)
        iex> {:ok, order} = Choreo.Analysis.topological_sort(system)
        iex> order
        [:ingest, :transform, :store]

    This analysis answers the question: "In what order should I deploy or initialise services?"
  """
  @spec topological_sort(Choreo.t()) :: {:ok, [Yog.node_id()]} | {:error, String.t()}
  def topological_sort(%Choreo{} = system) do
    graph = Choreo.to_simple_graph(system)

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
  def cyclic?(%Choreo{} = system) do
    system |> Choreo.to_simple_graph() |> Yog.cyclic?()
  end

  @doc """
    Returns `true` if the system is a Directed Acyclic Graph (DAG).
    This analysis answers the question: "Can I safely order my services linearly?"
  """
  @spec dag?(Choreo.t()) :: boolean()
  def dag?(%Choreo{} = system) do
    system |> Choreo.to_simple_graph() |> Yog.acyclic?()
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
  def strongly_connected_components(%Choreo{} = system) do
    system |> Choreo.to_simple_graph() |> Yog.Connectivity.strongly_connected_components()
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

        iex> system =
        ...>   Choreo.new()
        ...>   |> Choreo.add_service(:api)
        ...>   |> Choreo.add_service(:auth)
        ...>   |> Choreo.add_database(:db)
        ...>   |> Choreo.connect(:api, :auth)
        ...>   |> Choreo.connect(:auth, :db)
        iex> result = Choreo.Analysis.single_points_of_failure(system)
        iex> result.nodes
        [:auth]
        iex> result.edges
        [{:api, :auth}, {:auth, :db}]

    This analysis answers the question: "Which services or links would take down the whole system if they failed?"
  """
  @spec single_points_of_failure(Choreo.t()) :: %{
          nodes: [Yog.node_id()],
          edges: [{Yog.node_id(), Yog.node_id()}]
        }
  def single_points_of_failure(%Choreo{} = system) do
    graph = Choreo.to_simple_graph(system)
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

        iex> system =
        ...>   Choreo.new()
        ...>   |> Choreo.add_service(:api)
        ...>   |> Choreo.add_service(:auth)
        ...>   |> Choreo.add_database(:db)
        ...>   |> Choreo.connect(:api, :auth)
        ...>   |> Choreo.connect(:auth, :db)
        iex> Choreo.Analysis.impact_analysis(system, :db) |> Enum.sort()
        [:api, :auth]

    This analysis answers the question: "What breaks if this service goes down?"
  """
  @spec impact_analysis(Choreo.t(), Yog.node_id()) :: [Yog.node_id()]
  def impact_analysis(%Choreo{} = system, target) do
    graph = Choreo.to_simple_graph(system)
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

        iex> system =
        ...>   Choreo.new()
        ...>   |> Choreo.add_service(:api)
        ...>   |> Choreo.add_service(:auth)
        ...>   |> Choreo.add_database(:db)
        ...>   |> Choreo.connect(:api, :auth, cost: 5)
        ...>   |> Choreo.connect(:auth, :db, cost: 10)
        iex> {:ok, path} = Choreo.Analysis.shortest_path(system, :api, :db)
        iex> path.nodes
        [:api, :auth, :db]
        iex> path.weight
        15

    This analysis answers the question: "What is the fastest or cheapest route between two services?"
  """
  @spec shortest_path(Choreo.t(), Yog.node_id(), Yog.node_id(), keyword()) ::
          {:ok, map()} | :error
  def shortest_path(%Choreo{} = system, from, to, opts \\ []) do
    graph = Choreo.to_simple_graph(system)
    zero = Keyword.get(opts, :zero, 0)
    add = Keyword.get(opts, :add, &Kernel.+/2)
    compare = Keyword.get(opts, :compare, &Yog.Utils.compare/2)

    Yog.Pathfinding.Dijkstra.shortest_path(graph, from, to, zero, add, compare)
  end

  # ============================================================================
  # Centrality
  # ============================================================================

  @doc """
  Calculates centrality scores for nodes in the diagram.

  Centrality identifies the most important or "central" nodes in a graph.
  Supported measures include:

    * `:measure` — one of:
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

      iex> system = Choreo.new() |> Choreo.add_service(:a) |> Choreo.add_service(:b) |> Choreo.connect(:a, :b)
      iex> [{top, _}] = Choreo.Analysis.centrality(system, limit: 1)
      iex> top
      :a

  This analysis answers the question: "Which nodes are the most critical connectors?"
  """
  @spec centrality(struct(), keyword()) :: [{Yog.node_id(), float()}]
  def centrality(diagram, opts \\ []) do
    graph = get_simple_graph(diagram)
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

  @doc """
  Generates a "heat-mapped" version of a diagram by coloring nodes based on
  their centrality scores.

  ## Options

    * `:measure` — Centrality measure to use (`:degree`, `:betweenness`, etc.)
    * `:palette` — Color palette (`:heat`, `:cool`, `:spectral`)
    * All other options are passed to `centrality/2`.

  ## Examples

      # Highlight high-degree services in a system diagram
      system = Choreo.new() |> ...
      heat_system = Choreo.Analysis.heatmap(system, palette: :heat)

  This analysis answers the question: "Where are the hotspots in my architecture?"
  """
  @spec heatmap(struct(), keyword()) :: struct()
  def heatmap(diagram, opts \\ []) do
    palette = Keyword.get(opts, :palette, :heat)
    scores = Keyword.get(opts, :scores) || centrality(diagram, opts)

    if scores == [] do
      diagram
    else
      # Normalize scores to [0.0, 1.0]
      values = Enum.map(scores, &elem(&1, 1))
      min = Enum.min(values)
      max = Enum.max(values)
      range = max - min

      heatmapped =
        Enum.reduce(scores, diagram, fn {id, score}, acc ->
          norm = if range == 0, do: 1.0, else: (score - min) / range
          color = Choreo.Theme.color_from_scale(norm, palette)

          update_node_data(acc, id, fn data ->
            Map.put(data, :fillcolor, color)
          end)
        end)

      if Keyword.get(opts, :legend, false) do
        # We only support legend injection for Choreo structs for now
        # to avoid type mismatches in other diagram builders.
        # But we can provide a standalone legend function.
        heatmapped
      else
        heatmapped
      end
    end
  end

  @doc """
  Returns a standalone Choreo diagram acting as a color legend for a heatmap palette.

  ## Examples

      iex> legend = Choreo.Analysis.legend(:heat)
      iex> Choreo.to_dot(legend) =~ "Legend"
  """
  @spec legend(atom() | [String.t()]) :: Choreo.t()
  def legend(palette \\ :heat) do
    Choreo.new()
    |> Choreo.add_cluster("importance_legend", style: :dashed, label: "Importance Legend")
    |> Choreo.add_service(:low,
      name: "Low",
      cluster: "importance_legend",
      fillcolor: Choreo.Theme.color_from_scale(0.0, palette)
    )
    |> Choreo.add_service(:mid,
      name: "Medium",
      cluster: "importance_legend",
      fillcolor: Choreo.Theme.color_from_scale(0.5, palette)
    )
    |> Choreo.add_service(:high,
      name: "High",
      cluster: "importance_legend",
      fillcolor: Choreo.Theme.color_from_scale(1.0, palette)
    )
  end

  # ============================================================================
  # Isolated nodes
  # ============================================================================

  @doc """
    Returns nodes with no connections (zero in-degree and out-degree).

    Isolated services in an architecture diagram are usually a mistake —
    either a missing connection or an orphaned component.

    ## Examples

        iex> system =
        ...>   Choreo.new()
        ...>   |> Choreo.add_service(:connected)
        ...>   |> Choreo.add_service(:orphan)
        ...>   |> Choreo.connect(:connected, :connected)
        iex> Choreo.Analysis.isolated_nodes(system)
        [:orphan]

    This analysis answers the question: "Which services have no connections at all?"
  """
  @spec isolated_nodes(Choreo.t()) :: [Yog.node_id()]
  def isolated_nodes(%Choreo{} = system) do
    graph = Choreo.to_simple_graph(system)

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

        iex> system =
        ...>   Choreo.new()
        ...>   |> Choreo.add_service(:api)
        ...>   |> Choreo.add_service(:auth)
        ...>   |> Choreo.add_database(:db)
        ...>   |> Choreo.connect(:api, :auth)
        ...>   |> Choreo.connect(:auth, :db)
        iex> [{_severity, msg} | _rest] = Choreo.Analysis.validate(system)
        iex> String.contains?(msg, "Bridge edges")
        true

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

  defp check_cycles(acc, %Choreo{} = system) do
    graph = Choreo.to_simple_graph(system)

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

  defp get_simple_graph(diagram) do
    cond do
      function_exported?(diagram.__struct__, :to_simple_graph, 1) ->
        diagram.__struct__.to_simple_graph(diagram)

      function_exported?(diagram.__struct__, :to_simple_graph, 2) ->
        diagram.__struct__.to_simple_graph(diagram, [])

      Map.has_key?(diagram, :graph) and is_struct(diagram.graph, Yog.Graph) ->
        diagram.graph

      true ->
        raise ArgumentError, "Diagram type #{inspect(diagram.__struct__)} is not analysis-ready"
    end
  end

  defp update_node_data(diagram, id, fun) do
    new_graph =
      case diagram.graph do
        %Yog.Graph{nodes: nodes} = g ->
          %{g | nodes: Map.put(nodes, id, fun.(nodes[id]))}

        %Yog.Multi.Graph{nodes: nodes} = g ->
          %{g | nodes: Map.put(nodes, id, fun.(nodes[id]))}

        _ ->
          diagram.graph
      end

    %{diagram | graph: new_graph}
  end
end
