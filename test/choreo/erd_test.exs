defmodule Choreo.ERDTest do
  use ExUnit.Case, async: true

  alias Choreo.ERD
  alias Choreo.ERD.Analysis

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

  test "add_relationship validates existing nodes and options" do
    erd = ERD.new() |> ERD.add_table(:users, columns: [%{name: :id, type: :integer}])

    assert_raise ArgumentError, ~r/does not exist/, fn ->
      ERD.add_relationship(erd, :users, :posts, cardinality: :one_to_many)
    end

    assert_raise NimbleOptions.ValidationError, fn ->
      erd = ERD.add_table(erd, :posts, columns: [%{name: :id, type: :integer}])
      ERD.add_relationship(erd, :users, :posts, cardinality: :invalid)
    end
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
end
