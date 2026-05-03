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

    if not Yog.has_node?(diagram.graph, node) do
      raise ArgumentError, "Node #{inspect(node)} does not exist in diagram"
    end

    new_graph = Yog.ego_graph(diagram.graph, node, radius, mode: mode)
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

    case Yog.Pathfinding.Dijkstra.shortest_path(diagram.graph, from, to) do
      {:ok, path} ->
        path_nodes = path.nodes

        ids_to_keep =
          if radius > 0 do
            path_nodes
            |> Enum.flat_map(fn node ->
              ego = Yog.ego_graph(diagram.graph, node, radius, mode: :neighbors)
              Map.keys(ego.nodes)
            end)
            |> Enum.uniq()
          else
            path_nodes
          end

        new_graph = Yog.subgraph(diagram.graph, ids_to_keep)
        Choreo.Viewable.rebuild(diagram, new_graph)

      :error ->
        raise ArgumentError, "No path from #{inspect(from)} to #{inspect(to)}"
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

    new_graph = Yog.filter_nodes(diagram.graph, predicate)

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

    new_graph = Yog.subgraph(diagram.graph, ids_to_keep)

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
        |> Yog.add_node(new_id, Map.merge(%{label: label, node_type: :aggregate}, extra_data))
        |> rewire_collapsed_edges(ids_to_collapse, new_id)
        |> remove_collapsed_nodes(ids_to_collapse)

      Choreo.Viewable.rebuild(diagram, new_graph)
    end
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp validate_node_exists!(graph, node) do
    unless Yog.has_node?(graph, node) do
      raise ArgumentError, "Node #{inspect(node)} does not exist in diagram"
    end
  end

  defp rewire_collapsed_edges(graph, collapsed_ids, new_id) do
    collapsed_set = MapSet.new(collapsed_ids)

    # Collect all edges that need rewiring
    all_edges = Yog.all_edges(graph)

    # Remove all edges touching collapsed nodes, then add rewired ones
    graph_without_collapsed_edges =
      Enum.reduce(all_edges, graph, fn {from, to, _weight}, g ->
        if MapSet.member?(collapsed_set, from) or MapSet.member?(collapsed_set, to) do
          Yog.remove_edge(g, from, to)
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
        Yog.add_edge_ensure(g, from, to, weight)
      end
    end)
  end

  defp remove_collapsed_nodes(graph, collapsed_ids) do
    Enum.reduce(collapsed_ids, graph, &Yog.remove_node(&2, &1))
  end

  defp add_transitive_edges(original_graph, filtered_graph) do
    kept_ids = MapSet.new(Map.keys(filtered_graph.nodes))

    # For each pair of kept nodes, check if there was a path through
    # removed nodes and add a virtual edge if so.
    kept_list = MapSet.to_list(kept_ids)

    Enum.reduce(kept_list, filtered_graph, fn from, graph_acc ->
      Enum.reduce(kept_list, graph_acc, fn to, g_acc ->
        if from != to and not Yog.has_edge?(g_acc, from, to) do
          if reachable_through_removed?(original_graph, from, to, kept_ids) do
            Yog.add_edge_ensure(g_acc, from, to, 0)
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
        |> Yog.successor_ids(h)
        |> Enum.filter(fn succ ->
          not MapSet.member?(visited, succ) and
            (succ == target or not MapSet.member?(kept_ids, succ))
        end)

      new_visited = MapSet.union(visited, MapSet.new(next_nodes))
      do_reachable_bfs(graph, t ++ next_nodes, target, kept_ids, new_visited)
    end
  end
end
