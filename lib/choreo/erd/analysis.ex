defmodule Choreo.ERD.Analysis do
  @moduledoc """
  Analysis and topological query functions for `Choreo.ERD`.

  Provides graph algorithms optimized for database schema design, including:
    * `orphans/1` — finds disconnected tables.
    * `cycles/1` — identifies circular foreign key references.
    * `table_degrees/1` — measures coupling (incoming/outgoing links).
    * `shortest_join_path/3` — calculates the optimal join sequence between two tables.
    * `normalization_score/2` — scores schema health and reports normalization smells.
    * `validate/1` — returns structural and normalization issues as `{severity, message}` tuples.
    * `affected_by/2` — returns tables that transitively reference a target table.
    * `depends_on/2` — returns tables that the target table transitively relates to.
    * `transitive_reduction/1` — finds redundant relationships implied by longer paths.
    * `longest_dependency_chain/1` — finds the longest cascade of relationships.
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

  Returns a list of cycles, where each cycle is a list of node IDs
  starting at the canonical smallest node and listing each member once.

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
    Choreo.Internal.dfs_cycles(erd.graph)
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
  Returns all tables that transitively depend on the given table.

  If you change `target`, these are the tables that could break.

  ## Examples

      iex> erd =
      ...>   Choreo.ERD.new()
      ...>   |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:posts, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:comments, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_relationship(:users, :posts, cardinality: :one_to_many)
      ...>   |> Choreo.ERD.add_relationship(:posts, :comments, cardinality: :one_to_many)
      iex> Enum.sort(Choreo.ERD.Analysis.affected_by(erd, :comments))
      [:posts, :users]
      iex> Choreo.ERD.Analysis.affected_by(erd, :users)
      []

  This analysis answers the question: "What breaks if I change this table?"
  """
  @spec affected_by(Choreo.ERD.t(), Choreo.ERD.table_id()) :: [Choreo.ERD.table_id()]
  def affected_by(%Choreo.ERD{} = erd, target) do
    simple_graph = Yog.Multi.to_simple_graph(erd.graph)
    transposed = Yog.transpose(simple_graph)

    Choreo.Internal.bfs_reachable(transposed, [target])
    |> MapSet.to_list()
    |> List.delete(target)
    |> Enum.sort()
  end

  @doc """
  Returns all tables that the given table transitively depends on.

  These are the tables `target` cannot function without, following the
  directed relationships in the diagram.

  ## Examples

      iex> erd =
      ...>   Choreo.ERD.new()
      ...>   |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:posts, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:comments, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_relationship(:users, :posts, cardinality: :one_to_many)
      ...>   |> Choreo.ERD.add_relationship(:posts, :comments, cardinality: :one_to_many)
      iex> Enum.sort(Choreo.ERD.Analysis.depends_on(erd, :users))
      [:comments, :posts]
      iex> Choreo.ERD.Analysis.depends_on(erd, :comments)
      []

  This analysis answers the question: "What does this table depend on?"
  """
  @spec depends_on(Choreo.ERD.t(), Choreo.ERD.table_id()) :: [Choreo.ERD.table_id()]
  def depends_on(%Choreo.ERD{} = erd, target) do
    simple_graph = Yog.Multi.to_simple_graph(erd.graph)

    Choreo.Internal.bfs_reachable(simple_graph, [target])
    |> MapSet.to_list()
    |> List.delete(target)
    |> Enum.sort()
  end

  @doc """
  Identifies redundant relationships that are implied by a longer path.

  If `users -> posts`, `posts -> comments`, and `users -> comments` all
  exist, the direct `users -> comments` edge is redundant because it is
  implied by the transitive path.

  Returns a list of `{from, to}` tuples. On cyclic schemas returns an
  empty list because every edge in a cycle is structurally required.

  ## Examples

      iex> erd =
      ...>   Choreo.ERD.new()
      ...>   |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:posts, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:comments, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_relationship(:users, :posts, cardinality: :one_to_many)
      ...>   |> Choreo.ERD.add_relationship(:posts, :comments, cardinality: :one_to_many)
      ...>   |> Choreo.ERD.add_relationship(:users, :comments, cardinality: :one_to_many)
      iex> Choreo.ERD.Analysis.transitive_reduction(erd)
      [{:users, :comments}]

  This analysis answers the question: "Which explicit relationships are redundant?"
  """
  @spec transitive_reduction(Choreo.ERD.t()) :: [{Choreo.ERD.table_id(), Choreo.ERD.table_id()}]
  def transitive_reduction(%Choreo.ERD{} = erd) do
    erd.graph
    |> Yog.Multi.to_simple_graph()
    |> Choreo.Internal.transitive_reduction()
  end

  @doc """
  Finds the longest chain of relationships in the schema.

  This measures the maximum depth of foreign-key cascades and is useful
  for estimating migration, deletion, or query-plan complexity.

  Returns `{:ok, [table_id], total_edges}` or `:error` if the schema
  contains a cycle.

  ## Examples

      iex> erd =
      ...>   Choreo.ERD.new()
      ...>   |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:posts, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:comments, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_relationship(:users, :posts, cardinality: :one_to_many)
      ...>   |> Choreo.ERD.add_relationship(:posts, :comments, cardinality: :one_to_many)
      iex> Choreo.ERD.Analysis.longest_dependency_chain(erd)
      {:ok, [:users, :posts, :comments], 2}

  This analysis answers the question: "What is the deepest relationship chain?"
  """
  @spec longest_dependency_chain(Choreo.ERD.t()) ::
          {:ok, [Choreo.ERD.table_id()], number()} | :error
  def longest_dependency_chain(%Choreo.ERD{} = erd) do
    simple_graph = Yog.Multi.to_simple_graph(erd.graph)

    if Yog.cyclic?(simple_graph) do
      :error
    else
      case Yog.Traversal.Sort.topological_sort(simple_graph) do
        {:ok, order} ->
          dp = Choreo.Internal.compute_dp(simple_graph, order)

          case Choreo.Internal.find_best_end_path(dp) do
            nil ->
              :error

            {_dist, end_id} ->
              path = Choreo.Internal.reconstruct_path(dp, end_id)
              total = elem(Map.fetch!(dp, end_id), 0)
              {:ok, path, total}
          end

        {:error, :contains_cycle} ->
          :error
      end
    end
  end

  @doc """
  Validates a schema and returns a list of issues.

  Checks for:
    * unclassified orphan tables
    * direct many-to-many relationships without a junction table

  Returns a list of `{severity, message}` tuples.

  > ### Note on validation idiom
  > ERD uses `normalization_score/2` for quality scoring rather than a
  > binary pass/fail check. `validate/1` wraps the most critical smells
  > into the standard tuple format for composability with other modules.

  ## Examples

      iex> erd =
      ...>   Choreo.ERD.new()
      ...>   |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_table(:posts, columns: [%{name: :id, type: :integer}])
      ...>   |> Choreo.ERD.add_relationship(:users, :posts, cardinality: :many_to_many)
      iex> issues = Choreo.ERD.Analysis.validate(erd)
      iex> Enum.any?(issues, fn {sev, _} -> sev == :error end)
      true
  """
  @spec validate(Choreo.ERD.t()) :: [{:error | :warning, String.t()}]
  def validate(%Choreo.ERD{} = erd) do
    %{smells: smells} = normalization_score(erd)

    Enum.map(smells, fn smell ->
      if String.contains?(smell, "many-to-many") do
        {:error, smell}
      else
        {:warning, smell}
      end
    end)
  end

  @doc """
  Calculates a database normalization and schema quality score.

  The score starts at 100 and is reduced by:
    * `:large_column` — Tables with more than 15 columns (default: -15)
    * `:many_to_many` — Direct `:many_to_many` relationships without a junction table (default: -10)
    * `:one_to_one` — `:one_to_one` relationships indicating potential split entities (default: 0)
    * `:orphan` — Tables with no relationships (default: -10)

  > ### Opinionated defaults
  > The `:one_to_one` penalty defaults to 0 because legitimate 1-1 splits
  > (e.g., PII isolation) are common. Pass `weights: [one_to_one: 5]` to
  > opt-in to penalizing them.

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
        smells: ["Direct many-to-many relationship between :users and :posts."]
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
    one_to_one_penalty = Keyword.get(weights, :one_to_one, 0)
    orphan_penalty = Keyword.get(weights, :orphan, 10)

    column_threshold = Keyword.get(opts, :column_threshold, 15)

    {column_deductions, column_smells} =
      Enum.reduce(erd.graph.nodes, {0, []}, fn {table_id, data}, {deductions, smells} ->
        columns = Map.get(data, :columns, [])

        if length(columns) > column_threshold do
          {deductions + large_column_penalty,
           [
             "Table #{inspect(table_id)} has #{length(columns)} columns, exceeding the threshold of #{column_threshold}."
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
             [
               "Direct many-to-many relationship between #{inspect(from)} and #{inspect(to)}."
               | smells
             ]}

          cardinality == :one_to_one ->
            {deductions + one_to_one_penalty,
             [
               "One-to-one relationship between #{inspect(from)} and #{inspect(to)} suggests a potential split entity."
               | smells
             ]}

          true ->
            {deductions, smells}
        end
      end)

    {orphan_deductions, orphan_smells} =
      Enum.reduce(orphans(erd), {0, []}, fn table_id, {deductions, smells} ->
        {deductions + orphan_penalty,
         ["Table #{inspect(table_id)} is orphaned (has no relationships)." | smells]}
      end)

    total_deductions = column_deductions + relationship_deductions + orphan_deductions
    score = max(0, 100 - total_deductions)

    all_smells =
      (column_smells ++ relationship_smells ++ orphan_smells)
      |> Enum.sort()

    %{score: score, smells: all_smells}
  end
end
