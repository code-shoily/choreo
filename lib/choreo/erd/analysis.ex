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
      ...>   |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:posts, columns: [%{name: :id, type: :integer}, %{name: :user_id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:comments, columns: [%{name: :id, type: :integer}, %{name: :post_id, type: :integer}])
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
      simple_graph = Yog.Multi.to_simple_graph(erd.graph)
      undirected_graph = Yog.Transform.to_undirected(simple_graph, fn w1, w2 -> min(w1, w2) end)

      case Yog.Traversal.find_path(undirected_graph, start, dest) do
        nil -> :error
        path -> {:ok, path}
      end
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
      ...>   |> Choreo.ERD.add_table(:a, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:b, columns: [%{name: :id, type: :integer}])
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
      ...>   |> Choreo.ERD.add_table(:a, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:b, columns: [%{name: :id, type: :integer}])
      iex> Choreo.ERD.Analysis.orphans(erd)
      [:a, :b]
  """
  @spec orphans(Choreo.ERD.t()) :: [Choreo.ERD.table_id()]
  def orphans(%Choreo.ERD{} = erd) do
    erd.graph.nodes
    |> Map.keys()
    |> Enum.filter(fn node_id ->
      Yog.Multi.degree(erd.graph, node_id) == 0
    end)
    |> Enum.sort()
  end

  @doc """
  Calculates incoming, outgoing, and total degrees of all tables.

  Highly coupled tables with high degree counts (e.g. `users`) serve as central hubs,
  while tables with low degree counts represent leaves.

  ## Examples

      iex> erd =
      ...>   Choreo.ERD.new()
      ...>   |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:posts, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_relationship(:users, :posts, cardinality: :one_to_many)
      iex> Choreo.ERD.Analysis.table_degrees(erd)
      %{
        users: %{in: 0, out: 1, total: 1},
        posts: %{in: 1, out: 0, total: 1}
      }
  """
  @spec table_degrees(Choreo.ERD.t()) :: %{
          Choreo.ERD.table_id() => %{in: integer(), out: integer(), total: integer()}
        }
  def table_degrees(%Choreo.ERD{} = erd) do
    Map.new(erd.graph.nodes, fn {id, _data} ->
      in_deg = Yog.Multi.in_degree(erd.graph, id)
      out_deg = Yog.Multi.out_degree(erd.graph, id)
      {id, %{in: in_deg, out: out_deg, total: in_deg + out_deg}}
    end)
  end

  @doc """
  Calculates a database normalization and schema quality score.

  The score starts at 100 and is reduced by:
    * `:large_column` — Tables with more than 15 columns (default: -15)
    * `:many_to_many` — Direct `:many_to_many` relationships without a junction table (default: -10)
    * `:one_to_one` — `:one_to_one` relationships indicating potential split entities (default: -5)
    * `:orphan` — Tables with no relationships (default: -10)

  The score is capped at a minimum of 0.

  ## Options

    * `:weights` — Keyword list of custom penalties (e.g., `[large_column: 20, orphan: 5]`)
    * `:column_threshold` — Threshold for column count (default: 15)

  ## Examples

      iex> erd =
      ...>   Choreo.ERD.new()
      ...>   |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:posts, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_relationship(:users, :posts, cardinality: :many_to_many)
      iex> Choreo.ERD.Analysis.normalization_score(erd)
      %{
        score: 90,
        smells: ["Direct many-to-many relationship between 'users' and 'posts'."]
      }
  """
  @spec normalization_score(Choreo.ERD.t(), keyword()) :: %{
          score: number(),
          smells: [String.t()]
        }
  def normalization_score(%Choreo.ERD{} = erd, opts \\ []) do
    weights = Keyword.get(opts, :weights, [])
    large_column_penalty = Keyword.get(weights, :large_column, 15)
    many_to_many_penalty = Keyword.get(weights, :many_to_many, 10)
    one_to_one_penalty = Keyword.get(weights, :one_to_one, 5)
    orphan_penalty = Keyword.get(weights, :orphan, 10)

    column_threshold = Keyword.get(opts, :column_threshold, 15)

    {column_deductions, column_smells} =
      Enum.reduce(erd.graph.nodes, {0, []}, fn {table_id, data}, {deductions, smells} ->
        columns = Map.get(data, :columns, [])

        if length(columns) > column_threshold do
          {deductions + large_column_penalty,
           [
             "Table '#{table_id}' has #{length(columns)} columns, exceeding the threshold of #{column_threshold}."
             | smells
           ]}
        else
          {deductions, smells}
        end
      end)

    {relationship_deductions, relationship_smells} =
      Enum.reduce(erd.graph.edges, {0, []}, fn {edge_id, {from, to, _weight}},
                                               {deductions, smells} ->
        meta = Map.get(erd.edge_meta, edge_id, %{})
        cardinality = meta[:cardinality]

        cond do
          cardinality == :many_to_many ->
            {deductions + many_to_many_penalty,
             ["Direct many-to-many relationship between '#{from}' and '#{to}'." | smells]}

          cardinality == :one_to_one ->
            {deductions + one_to_one_penalty,
             [
               "One-to-one relationship between '#{from}' and '#{to}' suggests a potential split entity."
               | smells
             ]}

          true ->
            {deductions, smells}
        end
      end)

    {orphan_deductions, orphan_smells} =
      Enum.reduce(orphans(erd), {0, []}, fn table_id, {deductions, smells} ->
        {deductions + orphan_penalty,
         ["Table '#{table_id}' is orphaned (has no relationships)." | smells]}
      end)

    total_deductions = column_deductions + relationship_deductions + orphan_deductions
    score = max(0, 100 - total_deductions)

    all_smells =
      (column_smells ++ relationship_smells ++ orphan_smells)
      |> Enum.sort()

    %{score: score, smells: all_smells}
  end
end
