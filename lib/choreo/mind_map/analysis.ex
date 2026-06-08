defmodule Choreo.MindMap.Analysis do
  @moduledoc """
  Analysis functions for `Choreo.MindMap`.

  Provides algorithms that answer practical questions about a mind map:

    * How deep is the map? (max depth from root)
    * How broad is the map? (number of leaf nodes)
    * Which ideas are orphaned? (not reachable from root)
    * What are all root-to-leaf paths?
    * Is the map structurally sound?

  ## Further reading

    * [Mind map (Wikipedia)](https://en.wikipedia.org/wiki/Mind_map)
  """

  alias Choreo.MindMap

  @doc """
  Returns the maximum depth of the mind map (number of branch edges from
  root to deepest leaf).

  A single-node map has depth 0.

  Raises if the map contains a cycle — use `cyclic?/1` to check first.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a, label: "a")
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_subtopic(:c)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:b, :c)
      iex> Choreo.MindMap.Analysis.depth(map)
      2
      iex> Choreo.MindMap.Analysis.depth(Choreo.MindMap.new())
      0

  This analysis answers the question: "How deep is the mind map?"
  """
  @spec depth(MindMap.t()) :: non_neg_integer()
  def depth(%MindMap{root: nil}), do: 0

  def depth(%MindMap{} = map) do
    do_depth(map, map.root, 0, MapSet.new([map.root]))
  end

  @doc """
  Returns the number of leaf nodes (nodes with no outgoing branch edges).

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_topic(:c)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:a, :c)
      iex> Choreo.MindMap.Analysis.breadth(map)
      2

  This analysis answers the question: "How many leaf ideas exist?"
  """
  @spec breadth(MindMap.t()) :: non_neg_integer()
  def breadth(%MindMap{} = map) do
    length(leaves(map))
  end

  @doc """
  Returns all leaf node IDs (nodes with no outgoing branch edges).

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_topic(:c)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:a, :c)
      iex> Enum.sort(Choreo.MindMap.Analysis.leaves(map))
      [:b, :c]

  This analysis answers the question: "Which ideas have no children?"
  """
  @spec leaves(MindMap.t()) :: [Yog.node_id()]
  def leaves(%MindMap{} = map) do
    map.graph.nodes
    |> Enum.filter(fn {id, _data} ->
      branch_out_degree(map, id) == 0
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns nodes that are not reachable from the root via branch edges.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_topic(:c)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      iex> Choreo.MindMap.Analysis.orphan_nodes(map)
      [:c]

  This analysis answers the question: "Which ideas are disconnected from the root?"
  """
  @spec orphan_nodes(MindMap.t()) :: [Yog.node_id()]
  def orphan_nodes(%MindMap{root: nil}), do: []

  def orphan_nodes(%MindMap{} = map) do
    reachable = branch_reachable(map, [map.root])

    all = MindMap.nodes(map) |> MapSet.new()
    MapSet.difference(all, reachable) |> MapSet.to_list()
  end

  @doc """
  Returns the maximum number of nodes at any single depth level.

  Each node is counted at most once, at its shallowest depth from the root.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_topic(:c)
      ...>   |> Choreo.MindMap.add_topic(:d)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:a, :c)
      ...>   |> Choreo.MindMap.branch(:a, :d)
      iex> Choreo.MindMap.Analysis.max_width(map)
      3

  This analysis answers the question: "What is the widest level of the map?"
  """
  @spec max_width(MindMap.t()) :: non_neg_integer()
  def max_width(%MindMap{root: nil}), do: 0

  def max_width(%MindMap{} = map) do
    map
    |> nodes_by_depth()
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.max(fn -> 0 end)
  end

  @doc """
  Enumerates all root-to-leaf paths via branch edges.

  Each path is a list of node IDs from root to leaf.

  Raises if the map contains a cycle — use `cyclic?/1` to check first.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_subtopic(:c)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:b, :c)
      iex> Choreo.MindMap.Analysis.paths(map)
      [[:a, :b, :c]]

  This analysis answers the question: "What are all root-to-leaf paths?"
  """
  @spec paths(MindMap.t()) :: [[Yog.node_id()]]
  def paths(%MindMap{root: nil}), do: []

  def paths(%MindMap{} = map) do
    do_paths(map, map.root, [map.root], [], MapSet.new([map.root]))
  end

  @doc """
  Returns a map of node type frequencies.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_subtopic(:c)
      ...>   |> Choreo.MindMap.add_note(:d)
      iex> Choreo.MindMap.Analysis.type_frequencies(map)
      %{root: 1, topic: 1, subtopic: 1, note: 1}

  This analysis answers the question: "What is the composition of the map?"
  """
  @spec type_frequencies(MindMap.t()) :: %{atom() => non_neg_integer()}
  def type_frequencies(%MindMap{graph: graph}) do
    graph.nodes
    |> Enum.group_by(fn {_id, data} -> data[:node_type] || :unknown end)
    |> Enum.map(fn {type, nodes} -> {type, length(nodes)} end)
    |> Map.new()
  end

  @doc """
  Checks whether the mind map contains a directed cycle (considering all
  edges, including both branch and associative edges).

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_topic(:c)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:b, :c)
      ...>   |> Choreo.MindMap.branch(:c, :b)
      iex> Choreo.MindMap.Analysis.cyclic?(map)
      true

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      iex> Choreo.MindMap.Analysis.cyclic?(map)
      false

  This analysis answers the question: "Is there a cycle in the graph?"
  """
  @spec cyclic?(MindMap.t()) :: boolean()
  def cyclic?(%MindMap{graph: graph}) do
    Yog.cyclic?(graph)
  end

  @doc """
  Validates mind map structural soundness.

  Checks for:
    * missing root
    * cycles in the hierarchy
    * orphan nodes (not reachable from root)
    * nodes with multiple branch parents

  Returns a list of `{severity, message}` tuples.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.branch(:a, :b)
      iex> Choreo.MindMap.Analysis.validate(map)
      []

      iex> map = Choreo.MindMap.new()
      iex> Choreo.MindMap.Analysis.validate(map)
      [{:error, "Mind map has no root"}]

  This analysis answers the question: "Is the mind map structurally sound?"
  """
  @spec validate(MindMap.t()) :: [{:error | :warning, String.t()}]
  def validate(%MindMap{} = map) do
    []
    |> check_root(map)
    |> check_cycles(map)
    |> check_orphans(map)
    |> check_multiple_parents(map)
  end

  @doc """
  Suggests candidate node pairs for merging based on neighborhood Jaccard similarity.

  Two nodes are similar if they share a high percentage of neighbors (parents,
  children, and associates).

  Returns a list of tuples `[{node_a, node_b, similarity}]` sorted by similarity descending.

  ## Options

    * `:threshold` — minimum Jaccard similarity index to suggest (default: `0.5`)

  ## Examples

      iex> map = Choreo.MindMap.new()
      ...>   |> Choreo.MindMap.set_root(:root)
      ...>   |> Choreo.MindMap.add_topic(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_subtopic(:c)
      ...>   |> Choreo.MindMap.branch(:root, :a)
      ...>   |> Choreo.MindMap.branch(:root, :b)
      ...>   |> Choreo.MindMap.branch(:a, :c)
      ...>   |> Choreo.MindMap.branch(:b, :c)
      iex> {:a, :b, 1.0} in Choreo.MindMap.Analysis.suggest_merges(map)
      true
  """
  @spec suggest_merges(MindMap.t(), keyword()) :: [{Yog.node_id(), Yog.node_id(), float()}]
  def suggest_merges(%MindMap{} = map, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.5)
    nodes = MindMap.nodes(map) |> Enum.sort()

    # Calculate all neighbors for each node (both predecessors and successors)
    neighbors_map =
      Map.new(nodes, fn id ->
        preds = Yog.predecessors(map.graph, id) |> Enum.map(fn {pred, _w} -> pred end)
        succs = Yog.successor_ids(map.graph, id)
        {id, MapSet.new(preds ++ succs)}
      end)

    # Calculate Jaccard similarity for all distinct pairs
    pairs = for n1 <- nodes, n2 <- nodes, n1 < n2, do: {n1, n2}

    pairs
    |> Enum.map(fn {n1, n2} ->
      set1 = Map.fetch!(neighbors_map, n1)
      set2 = Map.fetch!(neighbors_map, n2)

      intersection = MapSet.intersection(set1, set2) |> MapSet.size()
      union = MapSet.union(set1, set2) |> MapSet.size()

      similarity = if union == 0, do: 0.0, else: intersection / union
      {n1, n2, similarity}
    end)
    |> Enum.filter(fn {_n1, _n2, similarity} -> similarity >= threshold end)
    |> Enum.sort_by(fn {_, _, similarity} -> -similarity end)
  end

  # ============================================================================
  # Private helpers — depth
  # ============================================================================

  defp do_depth(_map, _current, depth, _visited) when depth > 10_000 do
    # Safety break for unexpected cycles
    depth
  end

  defp do_depth(map, current, depth, visited) do
    children =
      branch_successors(map, current)
      |> Enum.reject(&MapSet.member?(visited, &1))

    if children == [] do
      depth
    else
      visited = MapSet.union(visited, MapSet.new(children))

      children
      |> Enum.map(fn child -> do_depth(map, child, depth + 1, visited) end)
      |> Enum.max()
    end
  end

  # ============================================================================
  # Private helpers — paths
  # ============================================================================

  defp do_paths(_map, _current, _path, acc, _visited) when length(acc) > 10_000 do
    # Safety break for unexpected cycles
    acc
  end

  defp do_paths(map, current, path, acc, visited) do
    children =
      branch_successors(map, current)
      |> Enum.reject(&MapSet.member?(visited, &1))

    if children == [] do
      [Enum.reverse(path) | acc]
    else
      visited = MapSet.union(visited, MapSet.new(children))

      Enum.reduce(children, acc, fn child, acc ->
        do_paths(map, child, [child | path], acc, visited)
      end)
    end
  end

  # ============================================================================
  # Private helpers — width / depth distribution
  # ============================================================================

  defp nodes_by_depth(map) do
    do_nodes_by_depth(map, map.root, 0, %{}, MapSet.new([map.root]))
  end

  defp do_nodes_by_depth(_map, nil, _depth, acc, _visited), do: acc

  defp do_nodes_by_depth(map, id, depth, acc, visited) do
    acc = Map.update(acc, depth, [id], &[id | &1])

    children =
      branch_successors(map, id)
      |> Enum.reject(&MapSet.member?(visited, &1))

    visited = MapSet.union(visited, MapSet.new(children))

    Enum.reduce(children, acc, fn child, acc ->
      do_nodes_by_depth(map, child, depth + 1, acc, visited)
    end)
  end

  # ============================================================================
  # Private helpers — branch graph utilities
  # ============================================================================

  defp branch_successors(map, id) do
    map.graph
    |> Yog.successor_ids(id)
    |> Enum.filter(fn succ ->
      meta = Map.get(map.edge_meta, {id, succ}, %{})
      meta[:edge_type] == :branch
    end)
  end

  defp branch_out_degree(map, id) do
    length(branch_successors(map, id))
  end

  defp branch_reachable(map, seeds) do
    do_bfs(map, seeds, MapSet.new(seeds))
  end

  defp do_bfs(_map, [], visited), do: visited

  defp do_bfs(map, [h | t], visited) do
    neighbors =
      branch_successors(map, h)
      |> Enum.reject(&MapSet.member?(visited, &1))

    do_bfs(map, t ++ neighbors, MapSet.union(visited, MapSet.new(neighbors)))
  end

  # ============================================================================
  # Private helpers — validation
  # ============================================================================

  defp check_root(acc, map) do
    if is_nil(map.root) do
      [{:error, "Mind map has no root"} | acc]
    else
      acc
    end
  end

  defp check_cycles(acc, map) do
    if cyclic?(map) do
      [{:error, "Cycle detected in mind map hierarchy"} | acc]
    else
      acc
    end
  end

  defp check_orphans(acc, map) do
    case orphan_nodes(map) do
      [] -> acc
      nodes -> [{:warning, "Orphan nodes: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_multiple_parents(acc, map) do
    violations =
      map.graph.nodes
      |> Enum.flat_map(fn {id, _data} ->
        branch_parents =
          map.graph
          |> Yog.predecessors(id)
          |> Enum.filter(fn {pred, _weight} ->
            meta = Map.get(map.edge_meta, {pred, id}, %{})
            meta[:edge_type] == :branch
          end)

        if length(branch_parents) > 1 do
          parent_ids = Enum.map(branch_parents, fn {pred, _weight} -> pred end)
          [{:warning, "Node #{inspect(id)} has multiple branch parents: #{inspect(parent_ids)}"}]
        else
          []
        end
      end)

    violations ++ acc
  end
end
