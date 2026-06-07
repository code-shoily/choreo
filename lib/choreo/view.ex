defmodule Choreo.View do
  @moduledoc """
  Graph lenses — zoom, focus, and filter any Choreo diagram.

  `Choreo.View` provides cross-module **view transforms** that produce
  new diagram structs without mutating the original. Think of it as
  "folding" or "zooming" a diagram — the same underlying graph, seen
  through a different focal length.

  Each diagram module must implement the `Choreo.Viewable` protocol to
  define how edge metadata is pruned, how roots are resolved, and what
  each zoom level means.

  ## Supported transforms

    * `focus/3` — keep a node and its N-hop neighbourhood
    * `focus_between/3` — keep only the shortest path between two nodes
    * `zoom/2` — filter by module-defined zoom level
    * `filter/2` — keep only nodes matching a predicate
    * `collapse/4` — aggregate multiple nodes into one

  ## When to use

  Use `Choreo.View` when you need:

    * **Context views** — show only high-level concepts before drilling down
    * **Focus views** — highlight one node and its immediate neighbours
    * **Path views** — trace the connection between two specific nodes
    * **Filtered exports** — remove notes or internal details for stakeholder decks

  ## Examples

      # Focus on the "Concurrency" topic and its neighbourhood
      focused = Choreo.View.focus(mind_map, :concurrency, radius: 2)

      # Show only the shortest path from root to a deep leaf
      path_view = Choreo.View.focus_between(mind_map, :root, :deep_leaf)

      # Zoom out to show only root and main topics
      overview = Choreo.View.zoom(mind_map, level: 1)

      # Hide all note nodes
      no_notes = Choreo.View.filter(mind_map, fn _id, data ->
        data[:node_type] != :note
      end)

      # Render the focused view
      dot = Choreo.MindMap.to_dot(focused)
  """

  @type viewable() :: struct()

  # ============================================================================
  # Focus — ego-graph view
  # ============================================================================

  @doc """
  Returns a new diagram containing only `node` and nodes within `radius` hops.

  ## Options

    * `:radius` — number of hops to include (default: `1`)
    * `:mode` — `:successors` (outgoing only), `:neighbors` (bidirectional),
      or `:predecessors` (incoming only). Default: `:neighbors`.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_subtopic(:c)
      ...>   |> Choreo.MindMap.add_subtopic(:d)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:b, :c)
      ...>   |> Choreo.MindMap.branch(:b, :d)
      iex> focused = Choreo.View.focus(map, :b, radius: 1)
      iex> Enum.sort(Choreo.MindMap.nodes(focused))
      [:a, :b, :c, :d]
  """
  @spec focus(viewable(), Yog.node_id(), keyword()) :: viewable()
  def focus(diagram, node, opts \\ []) do
    radius = Keyword.get(opts, :radius, 1)
    mode = Keyword.get(opts, :mode, :neighbors)

    if not graph_has_node?(diagram.graph, node) do
      raise ArgumentError, "Node #{inspect(node)} does not exist in diagram"
    end

    new_graph = graph_ego_graph(diagram.graph, node, radius, mode)
    Choreo.Viewable.rebuild(diagram, new_graph)
  end

  # ============================================================================
  # Focus between — shortest path view
  # ============================================================================

  @doc """
  Returns a new diagram containing only the shortest path from `from` to `to`.

  Optionally includes neighbours within `radius` hops of every node on the
  path.

  ## Options

    * `:radius` — include nodes within this many hops of each path node
      (default: `0`, meaning path nodes only)

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_subtopic(:c)
      ...>   |> Choreo.MindMap.add_topic(:d)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:b, :c)
      ...>   |> Choreo.MindMap.branch(:a, :d)
      iex> path = Choreo.View.focus_between(map, :a, :c)
      iex> Enum.sort(Choreo.MindMap.nodes(path))
      [:a, :b, :c]
  """
  @spec focus_between(viewable(), Yog.node_id(), Yog.node_id(), keyword()) :: viewable()
  def focus_between(diagram, from, to, opts \\ []) do
    radius = Keyword.get(opts, :radius, 0)

    validate_node_exists!(diagram.graph, from)
    validate_node_exists!(diagram.graph, to)

    case graph_shortest_path(diagram.graph, from, to) do
      {:ok, path} ->
        path_nodes = path.nodes

        ids_to_keep =
          if radius > 0 do
            path_nodes
            |> Enum.flat_map(fn node ->
              ego = graph_ego_graph(diagram.graph, node, radius, :neighbors)
              Map.keys(ego.nodes)
            end)
            |> Enum.uniq()
          else
            path_nodes
          end

        new_graph = graph_subgraph(diagram.graph, ids_to_keep)
        Choreo.Viewable.rebuild(diagram, new_graph)

      :error ->
        raise ArgumentError, "No path from #{inspect(from)} to #{inspect(to)}"
    end
  end

  # ============================================================================
  # Focus trace — trace path view
  # ============================================================================

  @doc """
  Returns a new diagram containing only the trace path from `from` to `to` (using
  trace edges).

  Optionally includes neighbors within `radius` hops of every node on the
  path in the full graph.

  ## Options

    * `:radius` — include nodes within this many hops of each path node
      in the full graph (default: `0`, meaning path nodes only)
  """
  @spec focus_trace(viewable(), Yog.node_id(), Yog.node_id(), keyword()) :: viewable()
  def focus_trace(diagram, from, to, opts \\ []) do
    radius = Keyword.get(opts, :radius, 0)

    validate_node_exists!(diagram.graph, from)
    validate_node_exists!(diagram.graph, to)

    case Choreo.Analysis.Tracing.trace_path(diagram, from, to) do
      {:ok, path_nodes} ->
        ids_to_keep =
          if radius > 0 do
            path_nodes
            |> Enum.flat_map(fn node ->
              ego = graph_ego_graph(diagram.graph, node, radius, :neighbors)
              Map.keys(ego.nodes)
            end)
            |> Enum.uniq()
          else
            path_nodes
          end

        new_graph = graph_subgraph(diagram.graph, ids_to_keep)
        Choreo.Viewable.rebuild(diagram, new_graph)

      :error ->
        raise ArgumentError, "No trace path from #{inspect(from)} to #{inspect(to)}"
    end
  end

  # ============================================================================
  # Zoom — level-based filtering
  # ============================================================================

  @doc """
  Returns a new diagram filtered to the given zoom level.

  Zoom levels are module-specific. Missing or unknown levels default to
  showing everything.

  ## Options

    * `:level` — zoom level (default: `3`, meaning "show everything")
    * `:transitive` — when `true`, adds virtual edges between remaining
      nodes that were connected through removed intermediate nodes.
      Default: `false`.

  ## MindMap levels

    * `0` — root only
    * `1` — root + topics
    * `2` — root + topics + subtopics
    * `3` (or higher) — everything including notes

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_subtopic(:c)
      ...>   |> Choreo.MindMap.add_note(:d)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:b, :c)
      ...>   |> Choreo.MindMap.branch(:c, :d)
      iex> zoomed = Choreo.View.zoom(map, level: 1)
      iex> Enum.sort(Choreo.MindMap.nodes(zoomed))
      [:a, :b]
  """
  @spec zoom(viewable(), keyword()) :: viewable()
  def zoom(diagram, opts \\ []) do
    level = Keyword.get(opts, :level, 3)
    transitive = Keyword.get(opts, :transitive, false)
    predicate = Choreo.Viewable.zoom_predicate(diagram, level)

    new_graph = graph_filter_nodes(diagram.graph, predicate)

    new_graph =
      if transitive do
        add_transitive_edges(diagram.graph, new_graph)
      else
        new_graph
      end

    Choreo.Viewable.rebuild(diagram, new_graph)
  end

  # ============================================================================
  # Filter — predicate-based node filtering
  # ============================================================================

  @doc """
  Returns a new diagram keeping only nodes that match `predicate`.

  `predicate` receives `{node_id, node_data}` and must return a boolean.

  ## Options

    * `:transitive` — when `true`, adds virtual edges between remaining
      nodes that were connected through removed intermediate nodes.
      Default: `false`.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_note(:c)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      iex> filtered = Choreo.View.filter(map, fn _id, data ->
      ...>   data[:node_type] != :note
      ...> end)
      iex> Enum.sort(Choreo.MindMap.nodes(filtered))
      [:a, :b]
  """
  @spec filter(viewable(), ({Yog.node_id(), map()} -> boolean()), keyword()) :: viewable()
  def filter(diagram, predicate, opts \\ []) do
    transitive = Keyword.get(opts, :transitive, false)

    ids_to_keep =
      diagram.graph.nodes
      |> Enum.filter(fn {id, data} -> predicate.(id, data) end)
      |> Enum.map(fn {id, _data} -> id end)

    new_graph = graph_subgraph(diagram.graph, ids_to_keep)

    new_graph =
      if transitive do
        add_transitive_edges(diagram.graph, new_graph)
      else
        new_graph
      end

    Choreo.Viewable.rebuild(diagram, new_graph)
  end

  # ============================================================================
  # Collapse — aggregate multiple nodes into one
  # ============================================================================

  @doc """
  Collapses all nodes matching `predicate` into a single aggregate node.

  All incoming and outgoing edges to/from the collapsed nodes are rewired
  to the aggregate. Self-loops and duplicate edges are removed.

  ## Options

    * `:label` — display label for the aggregate node (default: `"Aggregate"`)
    * `:data` — extra node data to merge (default: `%{}`)

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_topic(:c)
      ...>   |> Choreo.MindMap.add_subtopic(:d)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:a, :c)
      ...>   |> Choreo.MindMap.branch(:b, :d)
      ...>   |> Choreo.MindMap.branch(:c, :d)
      iex> collapsed = Choreo.View.collapse(map, fn id, _data -> id in [:b, :c] end, :topics)
      iex> Enum.sort(Choreo.MindMap.nodes(collapsed))
      [:a, :d, :topics]
      iex> Yog.has_edge?(collapsed.graph, :a, :topics)
      true
      iex> Yog.has_edge?(collapsed.graph, :topics, :d)
      true
  """
  @spec collapse(viewable(), ({Yog.node_id(), map()} -> boolean()), Yog.node_id(), keyword()) ::
          viewable()
  def collapse(diagram, predicate, new_id, opts \\ []) do
    ids_to_collapse =
      diagram.graph.nodes
      |> Enum.filter(fn {id, data} -> predicate.(id, data) end)
      |> Enum.map(fn {id, _data} -> id end)

    if ids_to_collapse == [] do
      diagram
    else
      label = Keyword.get(opts, :label, "Aggregate")
      extra_data = Keyword.get(opts, :data, %{})

      new_graph =
        diagram.graph
        |> graph_add_node(new_id, Map.merge(%{label: label, node_type: :aggregate}, extra_data))
        |> rewire_collapsed_edges(ids_to_collapse, new_id)
        |> remove_collapsed_nodes(ids_to_collapse)

      Choreo.Viewable.rebuild(diagram, new_graph)
    end
  end

  # ============================================================================
  # Graph-type dispatch helpers
  # ============================================================================

  defp graph_has_node?(%Yog.Multi.Graph{nodes: nodes}, id), do: Map.has_key?(nodes, id)
  defp graph_has_node?(graph, id), do: Yog.has_node?(graph, id)

  defp graph_successor_ids(%Yog.Multi.Graph{} = graph, id) do
    case Map.fetch(graph.out_edge_ids, id) do
      {:ok, edge_ids} ->
        Enum.map(edge_ids, fn eid ->
          {_, dst, _} = Map.fetch!(graph.edges, eid)
          dst
        end)
        |> Enum.uniq()

      :error ->
        []
    end
  end

  defp graph_successor_ids(graph, id) do
    if is_struct(graph, Yog.Multi.Graph) do
      case Map.get(graph.out_edge_ids, id) do
        nil ->
          []

        edge_ids ->
          Enum.map(edge_ids, fn eid ->
            {_, dest, _} = Map.get(graph.edges, eid)
            dest
          end)
          |> Enum.uniq()
      end
    else
      # credo:disable-for-next-line
      apply(Yog, :successor_ids, [graph, id])
    end
  end

  defp graph_predecessor_ids(graph, id) do
    if is_struct(graph, Yog.Multi.Graph) do
      case Map.get(graph.in_edge_ids, id) do
        nil ->
          []

        edge_ids ->
          Enum.map(edge_ids, fn eid ->
            {src, _, _} = Map.get(graph.edges, eid)
            src
          end)
          |> Enum.uniq()
      end
    else
      # credo:disable-for-next-line
      apply(Yog, :predecessors, [graph, id])
      |> Enum.map(fn {node_id, _data} -> node_id end)
    end
  end

  defp graph_all_edges(graph) do
    if is_struct(graph, Yog.Multi.Graph) do
      Map.values(graph.edges)
    else
      # credo:disable-for-next-line
      apply(Yog, :all_edges, [graph])
    end
  end

  defp graph_has_edge?(graph, from, to) do
    if is_struct(graph, Yog.Multi.Graph) do
      case Map.get(graph.out_edge_ids, from) do
        nil ->
          false

        edge_ids ->
          Enum.any?(edge_ids, fn eid ->
            {f, t, _} = Map.get(graph.edges, eid)
            f == from and t == to
          end)
      end
    else
      # credo:disable-for-next-line
      apply(Yog, :has_edge?, [graph, from, to])
    end
  end

  defp graph_add_node(%Yog.Multi.Graph{} = graph, id, data),
    do: Yog.Multi.add_node(graph, id, data)

  defp graph_add_node(graph, id, data), do: Yog.add_node(graph, id, data)

  defp graph_remove_node(%Yog.Multi.Graph{} = graph, id),
    do: Yog.Multi.remove_node(graph, id)

  defp graph_remove_node(graph, id), do: Yog.remove_node(graph, id)

  defp graph_add_edge(%Yog.Multi.Graph{} = graph, from, to, weight) do
    {new_graph, _eid} = Yog.Multi.add_edge(graph, from, to, weight)
    new_graph
  end

  defp graph_add_edge(graph, from, to, weight), do: Yog.add_edge_ensure(graph, from, to, weight)

  defp graph_remove_edge(%Yog.Multi.Graph{} = graph, from, to) do
    case Map.get(graph.out_edge_ids, from) do
      nil ->
        graph

      edge_ids ->
        to_remove =
          Enum.filter(edge_ids, fn eid ->
            {f, t, _} = Map.get(graph.edges, eid)
            f == from and t == to
          end)

        Enum.reduce(to_remove, graph, &Yog.Multi.remove_edge(&2, &1))
    end
  end

  defp graph_remove_edge(graph, from, to), do: Yog.remove_edge(graph, from, to)

  defp graph_ego_graph(%Yog.Multi.Graph{} = graph, node, radius, mode) do
    ids = multi_ego_collect(graph, node, radius, mode)
    multi_subgraph(graph, ids)
  end

  defp graph_ego_graph(graph, node, radius, mode) do
    Yog.ego_graph(graph, node, radius, mode: mode)
  end

  defp graph_filter_nodes(%Yog.Multi.Graph{} = graph, predicate) do
    kept_ids = for {id, data} <- graph.nodes, predicate.(id, data), do: id
    multi_subgraph(graph, kept_ids)
  end

  defp graph_filter_nodes(graph, predicate), do: Yog.filter_nodes(graph, predicate)

  defp graph_subgraph(%Yog.Multi.Graph{} = graph, ids), do: multi_subgraph(graph, ids)
  defp graph_subgraph(graph, ids), do: Yog.subgraph(graph, ids)

  defp graph_shortest_path(%Yog.Multi.Graph{} = graph, from, to) do
    # Build a simple graph with uniform numeric weights for pathfinding
    simple =
      Enum.reduce(graph.nodes, Yog.new(:directed), fn {id, data}, g ->
        Yog.add_node(g, id, data)
      end)

    simple =
      Enum.reduce(graph.edges, simple, fn {_eid, {src, dst, _data}}, g ->
        Yog.add_edge_ensure(g, src, dst, 1)
      end)

    Yog.Pathfinding.Dijkstra.shortest_path(simple, from, to)
  end

  defp graph_shortest_path(graph, from, to) do
    Yog.Pathfinding.Dijkstra.shortest_path(graph, from, to)
  end

  # ============================================================================
  # Multigraph-specific implementations
  # ============================================================================

  defp multi_subgraph(%Yog.Multi.Graph{} = graph, ids) do
    id_set = MapSet.new(ids)

    new_nodes = Map.take(graph.nodes, ids)

    new_edges =
      for {eid, {from, to, data}} <- graph.edges,
          MapSet.member?(id_set, from),
          MapSet.member?(id_set, to),
          into: %{},
          do: {eid, {from, to, data}}

    new_out_edge_ids =
      for {id, edge_set} <- graph.out_edge_ids,
          MapSet.member?(id_set, id),
          into: %{},
          do: {id, MapSet.filter(edge_set, &Map.has_key?(new_edges, &1))}

    new_in_edge_ids =
      for {id, edge_set} <- graph.in_edge_ids,
          MapSet.member?(id_set, id),
          into: %{},
          do: {id, MapSet.filter(edge_set, &Map.has_key?(new_edges, &1))}

    %Yog.Multi.Graph{
      graph
      | nodes: new_nodes,
        edges: new_edges,
        out_edge_ids: new_out_edge_ids,
        in_edge_ids: new_in_edge_ids
    }
  end

  defp multi_ego_collect(graph, start, radius, mode) do
    do_multi_ego_bfs(graph, [{start, 0}], radius, mode, MapSet.new([start]))
  end

  defp do_multi_ego_bfs(_graph, [], _radius, _mode, visited), do: MapSet.to_list(visited)

  defp do_multi_ego_bfs(graph, [{node, dist} | rest], radius, mode, visited) do
    if dist >= radius do
      do_multi_ego_bfs(graph, rest, radius, mode, visited)
    else
      neighbors =
        case mode do
          :successors ->
            graph_successor_ids(graph, node)

          :predecessors ->
            graph_predecessor_ids(graph, node)

          :neighbors ->
            (graph_successor_ids(graph, node) ++ graph_predecessor_ids(graph, node))
            |> Enum.uniq()
        end

      new_visited = MapSet.union(visited, MapSet.new(neighbors))
      new_queue = rest ++ Enum.map(neighbors, &{&1, dist + 1})
      do_multi_ego_bfs(graph, new_queue, radius, mode, new_visited)
    end
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp validate_node_exists!(graph, node) do
    unless graph_has_node?(graph, node) do
      raise ArgumentError, "Node #{inspect(node)} does not exist in diagram"
    end
  end

  defp rewire_collapsed_edges(graph, collapsed_ids, new_id) do
    collapsed_set = MapSet.new(collapsed_ids)

    # Collect all edges that need rewiring
    all_edges = graph_all_edges(graph)

    # Remove all edges touching collapsed nodes, then add rewired ones
    graph_without_collapsed_edges =
      Enum.reduce(all_edges, graph, fn {from, to, _weight}, g ->
        if MapSet.member?(collapsed_set, from) or MapSet.member?(collapsed_set, to) do
          graph_remove_edge(g, from, to)
        else
          g
        end
      end)

    # Add rewired edges: external -> collapsed becomes external -> new_id
    incoming_edges =
      all_edges
      |> Enum.filter(fn {from, to, _weight} ->
        not MapSet.member?(collapsed_set, from) and MapSet.member?(collapsed_set, to)
      end)
      |> Enum.map(fn {from, _to, weight} -> {from, new_id, weight} end)
      |> Enum.uniq()

    # Add rewired edges: collapsed -> external becomes new_id -> external
    outgoing_edges =
      all_edges
      |> Enum.filter(fn {from, to, _weight} ->
        MapSet.member?(collapsed_set, from) and not MapSet.member?(collapsed_set, to)
      end)
      |> Enum.map(fn {_from, to, weight} -> {new_id, to, weight} end)
      |> Enum.uniq()

    rewired = incoming_edges ++ outgoing_edges

    Enum.reduce(rewired, graph_without_collapsed_edges, fn {from, to, weight}, g ->
      if from == to do
        g
      else
        graph_add_edge(g, from, to, weight)
      end
    end)
  end

  defp remove_collapsed_nodes(graph, collapsed_ids) do
    Enum.reduce(collapsed_ids, graph, &graph_remove_node(&2, &1))
  end

  defp add_transitive_edges(original_graph, filtered_graph) do
    kept_ids = MapSet.new(Map.keys(filtered_graph.nodes))

    # For each pair of kept nodes, check if there was a path through
    # removed nodes and add a virtual edge if so.
    kept_list = MapSet.to_list(kept_ids)

    Enum.reduce(kept_list, filtered_graph, fn from, graph_acc ->
      Enum.reduce(kept_list, graph_acc, fn to, g_acc ->
        if from != to and not graph_has_edge?(g_acc, from, to) do
          if reachable_through_removed?(original_graph, from, to, kept_ids) do
            graph_add_edge(g_acc, from, to, 0)
          else
            g_acc
          end
        else
          g_acc
        end
      end)
    end)
  end

  defp reachable_through_removed?(graph, from, to, kept_ids) do
    # BFS that can only traverse nodes NOT in kept_ids (the removed nodes),
    # except the start and end nodes themselves.
    do_reachable_bfs(graph, [from], to, kept_ids, MapSet.new([from]))
  end

  defp do_reachable_bfs(_graph, [], _target, _kept_ids, _visited), do: false

  defp do_reachable_bfs(graph, [h | t], target, kept_ids, visited) do
    if h == target do
      true
    else
      next_nodes =
        graph
        |> graph_successor_ids(h)
        |> Enum.filter(fn succ ->
          not MapSet.member?(visited, succ) and
            (succ == target or not MapSet.member?(kept_ids, succ))
        end)

      new_visited = MapSet.union(visited, MapSet.new(next_nodes))
      do_reachable_bfs(graph, t ++ next_nodes, target, kept_ids, new_visited)
    end
  end
end
