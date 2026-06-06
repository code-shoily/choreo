defmodule Choreo.ERDTest do
  use ExUnit.Case, async: true

  alias Choreo.ERD
  alias Choreo.ERD.Analysis
  doctest Choreo.ERD
  doctest Choreo.ERD.Analysis

  setup do
    erd =
      ERD.new()
      |> ERD.add_table(:users,
        columns: [
          %{name: :id, type: :integer, key: :pk},
          %{name: :email, type: :varchar, comment: "unique email"}
        ]
      )
      |> ERD.add_table(:posts,
        columns: [
          %{name: :id, type: :integer, key: :pk},
          %{name: :user_id, type: :integer, key: :fk},
          %{name: :title, type: :varchar}
        ]
      )
      |> ERD.add_table(:comments,
        columns: [
          %{name: :id, type: :integer, key: :pk},
          %{name: :post_id, type: :integer, key: :fk},
          %{name: :body, type: :text}
        ]
      )
      |> ERD.add_relationship(:users, :posts, cardinality: :one_to_many, label: "writes")
      |> ERD.add_relationship(:posts, :comments, cardinality: :one_to_many, label: "has")

    {:ok, erd: erd}
  end

  test "initializes empty ERD" do
    erd = ERD.new()
    assert %ERD{} = erd
    assert erd.graph.nodes == %{}
  end

  test "add_table validates columns and fields" do
    assert_raise NimbleOptions.ValidationError, fn ->
      ERD.new() |> ERD.add_table(:invalid, columns: [%{type: :integer}])
    end

    assert_raise ArgumentError, fn ->
      ERD.new() |> ERD.add_table(:invalid, columns: "not_a_list")
    end
  end

  test "add_relationship implicitly registers missing tables and validates options" do
    erd =
      ERD.new()
      |> ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      |> ERD.add_relationship(:users, :posts, cardinality: :one_to_many)

    assert Map.has_key?(erd.graph.nodes, :posts)
    assert Map.get(erd.graph.nodes, :posts).type == :table
    assert Map.get(erd.graph.nodes, :posts).columns == []
    assert Map.get(erd.graph.nodes, :posts).label == "posts"

    assert_raise NimbleOptions.ValidationError, fn ->
      ERD.add_relationship(erd, :users, :posts, cardinality: :invalid)
    end
  end

  test "add_relationship strict_column_matching validations" do
    # When strict_column_matching is active, from_column and to_column must be supplied
    erd_strict =
      ERD.new(strict_column_matching: true)
      |> ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      |> ERD.add_table(:posts, columns: [%{name: :user_id, type: :integer}])

    assert_raise ArgumentError, ~r/strict_column_matching is enabled/, fn ->
      ERD.add_relationship(erd_strict, :users, :posts, cardinality: :one_to_many)
    end

    # Should raise if column does not exist
    assert_raise ArgumentError, ~r/column :nonexistent does not exist/, fn ->
      ERD.add_relationship(erd_strict, :users, :posts,
        cardinality: :one_to_many,
        from_column: :nonexistent,
        to_column: :user_id
      )
    end

    # Should raise if column in destination table does not exist
    assert_raise ArgumentError, ~r/column :nonexistent does not exist/, fn ->
      ERD.add_relationship(erd_strict, :users, :posts,
        cardinality: :one_to_many,
        from_column: :id,
        to_column: :nonexistent
      )
    end

    # Should raise if datatype mismatch
    erd_mismatch =
      ERD.new()
      |> ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      |> ERD.add_table(:posts, columns: [%{name: :user_uuid, type: :varchar}])

    assert_raise ArgumentError, ~r/type mismatch/, fn ->
      ERD.add_relationship(erd_mismatch, :users, :posts,
        cardinality: :one_to_many,
        from_column: :id,
        to_column: :user_uuid
      )
    end

    # Should succeed if columns exist and types match
    erd_ok =
      ERD.add_relationship(erd_strict, :users, :posts,
        cardinality: :one_to_many,
        from_column: :id,
        to_column: :user_id
      )

    assert %ERD{} = erd_ok
  end

  test "to_dot rendering and HTML unquoting", %{erd: erd} do
    dot = ERD.to_dot(erd)

    # HTML table wrapping check
    assert dot =~ "label=<<TABLE"
    assert dot =~ "users"
    assert dot =~ "posts"
    assert dot =~ "comments"
    assert dot =~ "writes"

    # Columns rendered properly inside HTML rows
    assert dot =~ "email"
    assert dot =~ "<i>varchar</i>"
    assert dot =~ "<b>[PK]</b>"
    assert dot =~ "&lt;unique email&gt;"

    # Cardinality arrow shapes
    assert dot =~ "arrowtail=\"teetee\""
    assert dot =~ "arrowhead=\"crowodot\""
    assert dot =~ "dir=\"both\""
  end

  test "to_dot custom themes", %{erd: erd} do
    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert ERD.to_dot(erd, theme: theme) =~ "label=<<TABLE"
    end
  end

  test "to_dot highlighting", %{erd: erd} do
    dot = ERD.to_dot(erd, highlighted_nodes: [:users], highlighted_edges: [0])
    assert dot =~ "users [label=<<TABLE"
    assert dot =~ "color=\"#ef4444\""
  end

  test "to_mermaid native erDiagram rendering", %{erd: erd} do
    mermaid = ERD.to_mermaid(erd)

    assert mermaid =~ "erDiagram"
    assert mermaid =~ "users {"
    assert mermaid =~ "integer id PK"
    assert mermaid =~ "varchar email \"unique email\""
    assert mermaid =~ "users ||--o{ posts : \"writes\""
    assert mermaid =~ "posts ||--o{ comments : \"has\""
  end

  test "shortest join path BFS", %{erd: erd} do
    assert Analysis.shortest_join_path(erd, :users, :comments) ==
             {:ok, [:users, :posts, :comments]}

    assert Analysis.shortest_join_path(erd, :users, :users) == {:ok, [:users]}

    # Add an isolated table
    erd = ERD.add_table(erd, :logs, columns: [%{name: :id, type: :integer}])
    assert Analysis.shortest_join_path(erd, :users, :logs) == :error
  end

  test "cycle detection" do
    erd =
      ERD.new()
      |> ERD.add_table(:a, columns: [%{name: :id, type: :integer}])
      |> ERD.add_table(:b, columns: [%{name: :id, type: :integer}])
      |> ERD.add_table(:c, columns: [%{name: :id, type: :integer}])
      |> ERD.add_relationship(:a, :b, cardinality: :one_to_one)
      |> ERD.add_relationship(:b, :c, cardinality: :one_to_one)
      |> ERD.add_relationship(:c, :a, cardinality: :one_to_one)

    assert Analysis.cycles(erd) == [[:a, :b, :c]]

    erd_no_cycles =
      ERD.new()
      |> ERD.add_table(:a, columns: [%{name: :id, type: :integer}])
      |> ERD.add_table(:b, columns: [%{name: :id, type: :integer}])
      |> ERD.add_relationship(:a, :b, cardinality: :one_to_one)

    assert Analysis.cycles(erd_no_cycles) == []
  end

  test "orphan detection", %{erd: erd} do
    assert Analysis.orphans(erd) == []

    erd = ERD.add_table(erd, :logs, columns: [%{name: :id, type: :integer}])
    assert Analysis.orphans(erd) == [:logs]
  end

  test "table degrees", %{erd: erd} do
    degrees = Analysis.table_degrees(erd)

    assert degrees[:users] == %{in: 0, out: 1, total: 1}
    assert degrees[:posts] == %{in: 1, out: 1, total: 2}
    assert degrees[:comments] == %{in: 1, out: 0, total: 1}
  end

  test "viewable protocol implementation", %{erd: erd} do
    assert Choreo.Viewable.zoom_predicate(erd, 1) != nil
    assert Choreo.Viewable.virtual_edge_meta(erd) != nil

    # Rebuild
    rebuilt = Choreo.Viewable.rebuild(erd, erd.graph)
    assert rebuilt.graph == erd.graph
    assert rebuilt.edge_meta == erd.edge_meta
  end

  describe "hardened edge cases" do
    test "to_dot/2 handles table names with spaces and special characters" do
      erd =
        ERD.new()
        |> ERD.add_table("my table", columns: [])
        |> ERD.add_table("another-table!", columns: [])
        |> ERD.add_relationship("my table", "another-table!", cardinality: :one_to_many)

      dot = ERD.to_dot(erd)
      assert String.contains?(dot, "\"my table\"")
      assert String.contains?(dot, "\"another-table!\"")
    end

    test "to_mermaid/2 handles table names with spaces and special characters" do
      erd =
        ERD.new()
        |> ERD.add_table("my table", columns: [])
        |> ERD.add_table("another-table!", columns: [])
        |> ERD.add_relationship("my table", "another-table!", cardinality: :one_to_many)

      mermaid = ERD.to_mermaid(erd)
      assert String.contains?(mermaid, "my table")
      assert String.contains?(mermaid, "another-table!")
    end
  end

  describe "normalization_score/2" do
    test "perfect schema receives a score of 100" do
      erd =
        ERD.new()
        |> ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
        |> ERD.add_table(:posts, columns: [%{name: :id, type: :integer}])
        |> ERD.add_relationship(:users, :posts, cardinality: :one_to_many)

      result = Analysis.normalization_score(erd)
      assert result.score == 100
      assert result.smells == []
    end

    test "detects orphans, one-to-one, and large columns" do
      columns = Enum.map(1..18, fn i -> %{name: :"col_#{i}", type: :integer} end)

      erd =
        ERD.new()
        # Large column count table
        |> ERD.add_table(:god_table, columns: columns)
        # Orphan table
        |> ERD.add_table(:lonely_table, columns: [%{name: :id, type: :integer}])
        # One-to-one relationship tables
        |> ERD.add_table(:a, columns: [%{name: :id, type: :integer}])
        |> ERD.add_table(:b, columns: [%{name: :id, type: :integer}])
        |> ERD.add_relationship(:a, :b, cardinality: :one_to_one)

      result = Analysis.normalization_score(erd)
      # Deductions:
      # :god_table has 18 columns (> 15) -> -15 points
      # :lonely_table is orphan -> -10 points
      # :god_table is orphan -> -10 points
      # :a -> :b is :one_to_one -> -5 points
      # Total: 100 - (15 + 10 + 10 + 5) = 60
      assert result.score == 60
      assert length(result.smells) == 4

      assert Enum.at(result.smells, 0) ==
               "One-to-one relationship between 'a' and 'b' suggests a potential split entity."

      assert Enum.at(result.smells, 1) ==
               "Table 'god_table' has 18 columns, exceeding the threshold of 15."

      assert Enum.at(result.smells, 2) == "Table 'god_table' is orphaned (has no relationships)."

      assert Enum.at(result.smells, 3) ==
               "Table 'lonely_table' is orphaned (has no relationships)."
    end

    test "respects custom weights and thresholds" do
      columns = Enum.map(1..6, fn i -> %{name: :"col_#{i}", type: :integer} end)

      erd =
        ERD.new()
        |> ERD.add_table(:users, columns: columns)
        |> ERD.add_table(:posts, columns: [%{name: :id, type: :integer}])
        |> ERD.add_relationship(:users, :posts, cardinality: :many_to_many)

      # Test custom column threshold and custom many-to-many weight
      result =
        Analysis.normalization_score(erd,
          column_threshold: 5,
          weights: [large_column: 40, many_to_many: 25]
        )

      # Deductions:
      # :users has 6 columns (> 5) -> -40 points
      # :many_to_many relationship -> -25 points
      # Total: 100 - 65 = 35
      assert result.score == 35
      assert length(result.smells) == 2
    end

    test "score is capped at 0" do
      erd =
        ERD.new()
        |> ERD.add_table(:a, columns: [])
        |> ERD.add_table(:b, columns: [])
        |> ERD.add_relationship(:a, :b, cardinality: :many_to_many)

      # 1 many_to_many (120) = 120 points deduction
      result = Analysis.normalization_score(erd, weights: [many_to_many: 120])
      assert result.score == 0
    end
  end
end
