defmodule Choreo.Analysis.Tracing do
  @moduledoc """
  Analysis functions for cross-diagram semantic tracing in Choreo.
  """

  alias Choreo

  @doc """
  Returns a list of all nodes that are transitively impacted by `target_id`
  along trace edges.
  """
  @spec impact_analysis(Choreo.t(), Yog.node_id()) :: [Yog.node_id()]
  def impact_analysis(%Choreo{} = system, target_id) do
    trace_graph = build_trace_only_graph(system)
    transposed = Yog.transpose(trace_graph)

    if Yog.has_node?(transposed, target_id) do
      transposed
      |> Yog.Traversal.walk(target_id, :breadth_first)
      |> List.delete(target_id)
    else
      []
    end
  end

  @doc """
  Finds the tracing path (sequence of nodes) from `from` to `to` using trace edges.
  """
  @spec trace_path(Choreo.t(), Yog.node_id(), Yog.node_id()) :: {:ok, [Yog.node_id()]} | :error
  def trace_path(%Choreo{} = system, from, to) do
    trace_graph = build_trace_only_graph(system)

    case Yog.Pathfinding.Dijkstra.shortest_path(trace_graph, from, to) do
      {:ok, path} -> {:ok, path.nodes}
      :error -> :error
    end
  end

  defp build_trace_only_graph(system) do
    simple = Yog.new(:directed)

    simple =
      Enum.reduce(system.graph.nodes, simple, fn {id, data}, g ->
        Yog.add_node(g, id, data)
      end)

    Enum.reduce(system.graph.edges, simple, fn {edge_id, {src, dst, _weight}}, g ->
      meta = Map.get(system.edge_meta, edge_id, %{})

      if meta[:edge_type] == :trace do
        Yog.add_edge_ensure(g, src, dst, 1)
      else
        g
      end
    end)
  end
end
