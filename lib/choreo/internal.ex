defmodule Choreo.Internal do
  @moduledoc false

  @doc """
  Breadth-first search returning a MapSet of all reachable node IDs from seeds.
  """
  @spec bfs_reachable(Yog.graph(), [Yog.node_id()]) :: MapSet.t(Yog.node_id())
  def bfs_reachable(graph, seeds) do
    do_bfs(graph, seeds, MapSet.new(seeds))
  end

  defp do_bfs(_graph, [], visited), do: visited

  defp do_bfs(graph, [h | t], visited) do
    neighbors =
      graph
      |> Yog.successor_ids(h)
      |> Enum.reject(&MapSet.member?(visited, &1))

    do_bfs(graph, t ++ neighbors, MapSet.union(visited, MapSet.new(neighbors)))
  end

  @doc """
  Builds cluster subgraph definitions from a struct that has:
    * `.graph` with `.nodes` containing `:cluster` metadata
    * `.clusters` map with cluster definitions

  Returns a list of subgraph maps compatible with `Yog.Render.DOT`.
  """
  @spec build_cluster_subgraphs(map(), Choreo.Theme.t()) :: [map()]
  def build_cluster_subgraphs(struct, theme) do
    clusters = struct.clusters || %{}

    if map_size(clusters) == 0 do
      []
    else
      nodes_by_cluster =
        struct.graph.nodes
        |> Enum.group_by(fn {_id, data} -> data[:cluster] end)
        |> Map.delete(nil)

      root_names =
        clusters
        |> Map.keys()
        |> Enum.filter(fn name ->
          parent = clusters[name][:parent]
          is_nil(parent) or not Map.has_key?(clusters, ensure_cluster_prefix(parent))
        end)

      Enum.map(root_names, &build_cluster(&1, clusters, nodes_by_cluster, theme))
    end
  end

  defp build_cluster(name, clusters, nodes_by_cluster, theme) do
    cluster = Map.get(clusters, name, %{})

    children_names =
      clusters
      |> Enum.filter(fn {_k, v} ->
        v[:parent] == name or ensure_cluster_prefix(v[:parent]) == name
      end)
      |> Enum.map(fn {k, _v} -> k end)

    children = Enum.map(children_names, &build_cluster(&1, clusters, nodes_by_cluster, theme))

    %{
      name: name,
      label: cluster[:label] || name,
      node_ids: nodes_by_cluster |> Map.get(name, []) |> Enum.map(fn {id, _data} -> id end),
      style: cluster[:style] || theme.cluster_style,
      fillcolor: cluster[:fillcolor] || theme.cluster_fillcolor,
      color: cluster[:color] || theme.cluster_color,
      subgraphs: if(children == [], do: nil, else: children)
    }
  end

  @doc """
  Finds the best predecessor for a node in a DP longest-path computation.
  """
  @spec best_predecessor(Yog.graph(), Yog.node_id(), map()) :: {number(), Yog.node_id()} | nil
  def best_predecessor(graph, id, acc) do
    preds = Yog.predecessors(graph, id)

    Enum.reduce(preds, nil, fn {pred, weight}, current_best ->
      case Map.fetch(acc, pred) do
        {:ok, {dist, _}} ->
          candidate = dist + weight

          if is_nil(current_best) or candidate > elem(current_best, 0) do
            {candidate, pred}
          else
            current_best
          end

        :error ->
          current_best
      end
    end)
  end

  defp ensure_cluster_prefix(name) do
    name = to_string(name)
    if String.starts_with?(name, "cluster_"), do: name, else: "cluster_#{name}"
  end
end
