defmodule Choreo.ERD.Analysis do
  @moduledoc """
  Analysis and topological query functions for `Choreo.ERD`.

  Provides graph algorithms optimized for database schema design, including:
    * `orphans/1` — finds disconnected tables.
    * `cycles/1` — identifies circular foreign key references.
    * `table_degrees/1` — measures coupling (incoming/outgoing links).
    * `shortest_join_path/3` — calculates the optimal join sequence between two tables.
  """

  @doc """
  Finds the shortest sequence of tables required to perform a join between
  `start` and `dest`.

  This treats the schema as an undirected graph, as joins can be traversed
  in either direction regardless of which table holds the foreign key.

  Returns `{:ok, path}` where `path` is a list of table IDs, or `:error` if
  the tables are not connected.

  ## Examples

      iex> erd =
      ...>   Choreo.ERD.new()
      ...>   |> Choreo.ERD.add_table(:users, columns: [id: :integer])
      ...>   |> Choreo.ERD.add_table(:posts, columns: [id: :integer, user_id: :integer])
      ...>   |> Choreo.ERD.add_table(:comments, columns: [id: :integer, post_id: :integer])
      ...>   |> Choreo.ERD.add_relationship(:users, :posts, cardinality: :one_to_many)
      ...>   |> Choreo.ERD.add_relationship(:posts, :comments, cardinality: :one_to_many)
      iex> Choreo.ERD.Analysis.shortest_join_path(erd, :users, :comments)
      {:ok, [:users, :posts, :comments]}
  """
  @spec shortest_join_path(Choreo.ERD.t(), Choreo.ERD.table_id(), Choreo.ERD.table_id()) ::
          {:ok, [Choreo.ERD.table_id()]} | :error
  def shortest_join_path(%Choreo.ERD{} = erd, start, dest) do
    if not Map.has_key?(erd.graph.nodes, start) do
      raise ArgumentError, "table #{inspect(start)} does not exist in the diagram"
    end

    if not Map.has_key?(erd.graph.nodes, dest) do
      raise ArgumentError, "table #{inspect(dest)} does not exist in the diagram"
    end

    if start == dest do
      {:ok, [start]}
    else
      q = :queue.in({start, []}, :queue.new())

      case do_undirected_bfs(erd.graph, q, MapSet.new([start]), dest) do
        {:ok, path} -> {:ok, Enum.reverse([dest | path])}
        :error -> :error
      end
    end
  end

  defp do_undirected_bfs(graph, q, visited, dest) do
    case :queue.out(q) do
      {{:value, {current, path}}, rest_q} ->
        if current == dest do
          {:ok, path}
        else
          succs =
            Yog.Multi.successors(graph, current) |> Enum.map(fn {node, _eid, _w} -> node end)

          preds =
            Yog.Multi.predecessors(graph, current) |> Enum.map(fn {node, _eid, _w} -> node end)

          all_neighbors = Enum.uniq(succs ++ preds)

          {new_q, new_visited} =
            Enum.reduce(all_neighbors, {rest_q, visited}, fn nbr, {q_acc, v_acc} ->
              if MapSet.member?(v_acc, nbr) do
                {q_acc, v_acc}
              else
                {:queue.in({nbr, [current | path]}, q_acc), MapSet.put(v_acc, nbr)}
              end
            end)

          do_undirected_bfs(graph, new_q, new_visited, dest)
        end

      {:empty, _rest_q} ->
        :error
    end
  end

  @doc """
  Finds all circular foreign key references (directed cycles) in the ERD.

  Circular references can prevent clean database teardowns, complicate
  cascade triggers, and indicate suboptimal database normalization.

  Returns a list of cycles, where each cycle is represented by a sequence of
  table IDs starting and ending with the same node.

  ## Examples

      iex> erd =
      ...>   Choreo.ERD.new()
      ...>   |> Choreo.ERD.add_table(:a, columns: [id: :integer])
      ...>   |> Choreo.ERD.add_table(:b, columns: [id: :integer])
      ...>   |> Choreo.ERD.add_relationship(:a, :b, cardinality: :one_to_one)
      ...>   |> Choreo.ERD.add_relationship(:b, :a, cardinality: :one_to_one)
      iex> Choreo.ERD.Analysis.cycles(erd)
      [[:a, :b]]
  """
  @spec cycles(Choreo.ERD.t()) :: [[Choreo.ERD.table_id()]]
  def cycles(%Choreo.ERD{} = erd) do
    nodes = Map.keys(erd.graph.nodes)

    {cycles, _visited} =
      Enum.reduce(nodes, {[], MapSet.new()}, fn node, {cycles_acc, visited} ->
        {c, v} = dfs_cycles(erd.graph, node, visited, [], MapSet.new(), [])
        {cycles_acc ++ c, v}
      end)

    cycles
    |> Enum.map(&normalize_cycle/1)
    |> Enum.uniq()
  end

  defp dfs_cycles(graph, node, visited, path_list, path_set, cycles) do
    cond do
      MapSet.member?(path_set, node) ->
        cycle = [node | Enum.take_while(path_list, &(&1 != node)) |> Enum.reverse()]
        {[cycle | cycles], visited}

      MapSet.member?(visited, node) ->
        {cycles, visited}

      true ->
        path_set = MapSet.put(path_set, node)
        path_list = [node | path_list]

        successors =
          Yog.Multi.successors(graph, node) |> Enum.map(fn {dest, _eid, _w} -> dest end)

        {cycles, visited} =
          Enum.reduce(successors, {cycles, visited}, fn succ, {c_acc, v_acc} ->
            dfs_cycles(graph, succ, v_acc, path_list, path_set, c_acc)
          end)

        visited = MapSet.put(visited, node)
        {cycles, visited}
    end
  end

  defp normalize_cycle(cycle) do
    min_element = Enum.min(cycle)
    {left, right} = Enum.split_while(cycle, &(&1 != min_element))
    right ++ left
  end

  @doc """
  Finds all "orphan" tables that have no incoming or outgoing relationships.

  Orphan tables are structurally isolated from the rest of the database schema.

  ## Examples

      iex> erd =
      ...>   Choreo.ERD.new()
      ...>   |> Choreo.ERD.add_table(:a, columns: [id: :integer])
      ...>   |> Choreo.ERD.add_table(:b, columns: [id: :integer])
      iex> Choreo.ERD.Analysis.orphans(erd)
      [:a, :b]
  """
  @spec orphans(Choreo.ERD.t()) :: [Choreo.ERD.table_id()]
  def orphans(%Choreo.ERD{} = erd) do
    erd.graph.nodes
    |> Map.keys()
    |> Enum.filter(fn node_id ->
      Yog.Multi.successors(erd.graph, node_id) == [] and
        Yog.Multi.predecessors(erd.graph, node_id) == []
    end)
    |> Enum.sort()
  end

  @doc """
  Calculates incoming, outgoing, and total degrees of all tables.

  Highly coupled tables with high degree counts (e.g. `users`) serve as central hubs,
  while tables with low degree counts represent leaves.
  """
  @spec table_degrees(Choreo.ERD.t()) :: %{
          Choreo.ERD.table_id() => %{in: integer(), out: integer(), total: integer()}
        }
  def table_degrees(%Choreo.ERD{} = erd) do
    Map.new(erd.graph.nodes, fn {id, _data} ->
      out_deg = length(Yog.Multi.successors(erd.graph, id))
      in_deg = length(Yog.Multi.predecessors(erd.graph, id))
      {id, %{in: in_deg, out: out_deg, total: in_deg + out_deg}}
    end)
  end
end
