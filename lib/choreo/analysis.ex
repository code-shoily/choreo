defmodule Choreo.Analysis do
  @moduledoc """
  Graph-algorithm wrappers for `Choreo` architecture diagrams.

  These functions adapt the generic algorithms from `Yog` to the
  domain of system architecture.
  """

  alias Choreo

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
  """
  @spec cyclic?(Choreo.t()) :: boolean()
  def cyclic?(%Choreo{graph: graph}) do
    Yog.cyclic?(graph)
  end

  @doc """
  Returns `true` if the system is a Directed Acyclic Graph (DAG).
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
  """
  @spec strongly_connected_components(Choreo.t()) :: [[Yog.node_id()]]
  def strongly_connected_components(%Choreo{graph: graph}) do
    Yog.Connectivity.strongly_connected_components(graph)
  end
end
