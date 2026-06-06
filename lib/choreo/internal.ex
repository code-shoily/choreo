defmodule Choreo.Internal do
  @moduledoc false

  @doc """
  Breadth-first search returning a MapSet of all reachable node IDs from seeds.

  ## Examples

      iex> graph = Yog.new(:directed) |> Yog.add_node(:a, %{}) |> Yog.add_node(:b, %{}) |> Yog.add_node(:c, %{})
      ...> graph = Yog.add_edge_ensure(graph, :a, :b, 1)
      ...> graph = Yog.add_edge_ensure(graph, :b, :c, 1)
      iex> Choreo.Internal.bfs_reachable(graph, [:a]) |> MapSet.to_list() |> Enum.sort()
      [:a, :b, :c]
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

    base = %{
      name: name,
      label: cluster[:label] || name,
      node_ids: nodes_by_cluster |> Map.get(name, []) |> Enum.map(fn {id, _data} -> id end),
      style: cluster[:style] || theme.cluster_style,
      fillcolor: cluster[:fillcolor] || theme.cluster_fillcolor,
      color: cluster[:color] || theme.cluster_color,
      subgraphs: if(children == [], do: nil, else: children)
    }

    # Pass through any extra cluster attributes (e.g. penwidth from threat boundaries)
    overrides =
      cluster
      |> Map.drop([:label, :parent])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Map.merge(base, overrides)
  end

  @doc """
  Finds the best predecessor for a node in a DP longest-path computation.

  ## Examples

      iex> graph = Yog.new(:directed) |> Yog.add_node(:a, %{}) |> Yog.add_node(:b, %{}) |> Yog.add_node(:c, %{})
      ...> graph = Yog.add_edge_ensure(graph, :a, :b, 5)
      ...> graph = Yog.add_edge_ensure(graph, :a, :c, 10)
      iex> acc = %{a: {0, nil}, b: {5, :a}, c: {10, :a}}
      iex> Choreo.Internal.best_predecessor(graph, :b, acc)
      {5, :a}
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

  @doc false
  def ensure_cluster_prefix(name) do
    name = to_string(name)
    if String.starts_with?(name, "cluster_"), do: name, else: "cluster_#{name}"
  end

  @doc """
  Computes a longest-path DP table over a topologically sorted order.

  `seed_set` controls which nodes are treated as path origins:
    * `nil` — every node is a potential origin (unreachable nodes get `{0, nil}`)
    * `MapSet.t()` — only nodes in the set are origins; unreachable nodes are omitted

  ## Examples

      iex> graph = Yog.new(:directed) |> Yog.add_node(:a, %{}) |> Yog.add_node(:b, %{})
      ...> graph = Yog.add_edge_ensure(graph, :a, :b, 5)
      iex> Choreo.Internal.compute_dp(graph, [:a, :b], nil)
      %{a: {0, nil}, b: {5, :a}}
  """
  @spec compute_dp(Yog.graph(), [Yog.node_id()], MapSet.t(Yog.node_id()) | nil) :: %{
          optional(Yog.node_id()) => {number(), Yog.node_id() | nil}
        }
  def compute_dp(graph, order, seed_set \\ nil) do
    Enum.reduce(order, %{}, fn id, acc ->
      if seed_set && MapSet.member?(seed_set, id) do
        Map.put(acc, id, {0, nil})
      else
        best = best_predecessor(graph, id, acc)

        cond do
          best -> Map.put(acc, id, best)
          is_nil(seed_set) -> Map.put(acc, id, {0, nil})
          true -> acc
        end
      end
    end)
  end

  @doc """
  Finds the DP entry with the maximum distance.

  `candidate_set` restricts the search to specific nodes (e.g. sinks or ends).
  If `nil`, all entries in `dp` are considered.

  ## Examples

      iex> dp = %{a: {0, nil}, b: {5, :a}, c: {10, :a}}
      iex> Choreo.Internal.find_best_end_path(dp)
      {10, :c}
      iex> Choreo.Internal.find_best_end_path(dp, MapSet.new([:a, :b]))
      {5, :b}
  """
  @spec find_best_end_path(map(), MapSet.t(Yog.node_id()) | nil) ::
          {number(), Yog.node_id()} | nil
  def find_best_end_path(dp, candidate_set \\ nil) do
    if candidate_set do
      Enum.reduce(candidate_set, nil, fn id, current_best ->
        case Map.fetch(dp, id) do
          {:ok, {dist, _}} ->
            if is_nil(current_best) or dist > elem(current_best, 0) do
              {dist, id}
            else
              current_best
            end

          :error ->
            current_best
        end
      end)
    else
      Enum.reduce(dp, nil, fn {id, {dist, _}}, current_best ->
        if is_nil(current_best) or dist > elem(current_best, 0) do
          {dist, id}
        else
          current_best
        end
      end)
    end
  end

  @doc """
  Reconstructs a path from `end_id` back to an origin by following DP predecessors.

  ## Examples

      iex> dp = %{a: {0, nil}, b: {5, :a}, c: {10, :b}}
      iex> Choreo.Internal.reconstruct_path(dp, :c)
      [:a, :b, :c]
  """
  @spec reconstruct_path(map(), Yog.node_id()) :: [Yog.node_id()]
  def reconstruct_path(dp, end_id) do
    do_reconstruct(dp, end_id, [end_id])
  end

  defp do_reconstruct(_dp, nil, acc), do: acc

  defp do_reconstruct(dp, id, acc) do
    case Map.fetch(dp, id) do
      {:ok, {_dist, nil}} -> acc
      {:ok, {_dist, prev}} -> do_reconstruct(dp, prev, [prev | acc])
      :error -> acc
    end
  end

  @doc """
  Darkens a hex color code slightly for use as a stroke/border color.
  """
  @spec darken(String.t()) :: String.t()
  def darken("#" <> hex) when byte_size(hex) == 6 do
    hex
    |> String.to_integer(16)
    |> then(fn n ->
      r = max(0, div(n, 0x10000) - 30)
      g = max(0, div(rem(n, 0x10000), 0x100) - 30)
      b = max(0, rem(n, 0x100) - 30)
      <<r::8, g::8, b::8>>
    end)
    |> Base.encode16(case: :lower)
    |> then(&("#" <> &1))
  end

  def darken(other), do: other

  @doc """
  Converts a simple `Yog.Graph` to a `Yog.Multi.Graph`, returning `{multi_graph, edge_id_map}`.
  """
  @spec to_multi_graph(Yog.graph()) :: {Yog.Multi.Graph.t(), map()}
  def to_multi_graph(%Yog.Graph{} = graph) do
    multi = Yog.Multi.new(graph.kind)

    multi =
      Enum.reduce(graph.nodes, multi, fn {id, data}, acc ->
        Yog.Multi.add_node(acc, id, data)
      end)

    {multi, edge_id_map} =
      Enum.reduce(graph.out_edges, {multi, %{}}, fn {from, targets}, {g_acc, map_acc} ->
        Enum.reduce(targets, {g_acc, map_acc}, fn {to, weight}, {g2, m2} ->
          {g3, edge_id} = Yog.Multi.add_edge(g2, from, to, weight)
          {g3, Map.put(m2, edge_id, {from, to})}
        end)
      end)

    {multi, edge_id_map}
  end

  @doc """
  Builds cluster subgraph definitions for Mermaid flowchart compatibility.
  """
  @spec build_mermaid_subgraphs(map()) :: [map()]
  def build_mermaid_subgraphs(struct) do
    clusters = struct.clusters || %{}

    if map_size(clusters) == 0 do
      []
    else
      nodes_by_cluster =
        struct.graph.nodes
        |> Enum.group_by(fn {_id, data} -> data[:cluster] end)
        |> Map.delete(nil)

      Enum.flat_map(nodes_by_cluster, fn {cluster_name, nodes} ->
        cluster = Map.get(clusters, cluster_name, %{})
        label = cluster[:label] || cluster_name
        node_ids = Enum.map(nodes, fn {id, _data} -> id end)

        if node_ids == [] do
          []
        else
          [
            %{
              name: clean_cluster_name(cluster_name),
              label: label,
              node_ids: node_ids
            }
          ]
        end
      end)
    end
  end

  defp clean_cluster_name(name) do
    name = to_string(name)
    String.replace_prefix(name, "cluster_", "")
  end

  @doc """
  Rebuilds a multigraph to use mapped, safe node IDs.
  """
  @spec make_multi_graph_safe(Yog.Multi.Graph.t(), %{Yog.node_id() => String.t()}) ::
          Yog.Multi.Graph.t()
  def make_multi_graph_safe(graph, id_map) do
    new_nodes = Map.new(graph.nodes, fn {id, data} -> {Map.fetch!(id_map, id), data} end)

    new_edges =
      Map.new(graph.edges, fn {edge_id, {from, to, weight}} ->
        {edge_id, {Map.fetch!(id_map, from), Map.fetch!(id_map, to), weight}}
      end)

    new_out = Map.new(graph.out_edge_ids, fn {id, set} -> {Map.fetch!(id_map, id), set} end)
    new_in = Map.new(graph.in_edge_ids, fn {id, set} -> {Map.fetch!(id_map, id), set} end)

    %{graph | nodes: new_nodes, edges: new_edges, out_edge_ids: new_out, in_edge_ids: new_in}
  end

  @doc """
  Rebuilds a simple graph to use mapped, safe node IDs.
  """
  @spec make_simple_graph_safe(Yog.Graph.t(), %{Yog.node_id() => String.t()}) ::
          Yog.Graph.t()
  def make_simple_graph_safe(graph, id_map) do
    new_nodes = Map.new(graph.nodes, fn {id, data} -> {Map.fetch!(id_map, id), data} end)

    new_out =
      Map.new(graph.out_edges, fn {from, targets} ->
        new_targets =
          Map.new(targets, fn {to, weight} -> {Map.fetch!(id_map, to), weight} end)

        {Map.fetch!(id_map, from), new_targets}
      end)

    new_in =
      Map.new(graph.in_edges, fn {to, sources} ->
        new_sources =
          Map.new(sources, fn {from, weight} -> {Map.fetch!(id_map, from), weight} end)

        {Map.fetch!(id_map, to), new_sources}
      end)

    %{graph | nodes: new_nodes, out_edges: new_out, in_edges: new_in}
  end
end
