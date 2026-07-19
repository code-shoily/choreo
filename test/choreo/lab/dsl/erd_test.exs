defmodule Choreo.Lab.ERDDSLTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.ERD

  doctest Choreo.Lab.DSL.ERD

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.ERD.taxonomy()

    assert :table in taxonomy.tables
    assert :entity in taxonomy.tables
    assert :pk in taxonomy.columns
    assert :fk in taxonomy.columns
    assert :one_to_many in taxonomy.edges
    assert :has_many in taxonomy.edges
    assert :columns in taxonomy.modifiers
    assert :from_column in taxonomy.options
    assert Choreo.Lab.DSL.ERD.verbs() == taxonomy
  end

  test "builds an ERD with block-based table declarations" do
    schema =
      erd do
        users =
          table("users") do
            pk :id, :integer
            field :email, :varchar, comment: "unique email"
          end

        posts =
          table("posts") do
            pk :id, :integer
            fk :user_id, :integer
            field :title, :varchar
          end

        one_to_many users ~> posts, "writes", from: :id, to: :user_id
      end

    assert schema.graph.nodes[:users].label == "users"

    assert schema.graph.nodes[:users].columns == [
             [name: :id, type: :integer, key: :pk],
             [name: :email, type: :varchar, comment: "unique email"]
           ]

    assert schema.graph.nodes[:posts].columns == [
             [name: :id, type: :integer, key: :pk],
             [name: :user_id, type: :integer, key: :fk],
             [name: :title, type: :varchar]
           ]

    assert [{:users, :posts, 1}] = edge_tuples(schema.graph)
    assert [meta] = Map.values(schema.edge_meta)
    assert meta.cardinality == :one_to_many
    assert meta.label == "writes"
    assert meta.from_column == :id
    assert meta.to_column == :user_id
  end

  test "supports inline table constructors for one-off sketches" do
    schema =
      erd do
        table("users") ~> table("posts") |> one_to_many("writes")
      end

    assert Map.has_key?(schema.graph.nodes, :users)
    assert Map.has_key?(schema.graph.nodes, :posts)
    assert [meta] = Map.values(schema.edge_meta)
    assert meta.cardinality == :one_to_many
    assert meta.label == "writes"
  end

  test "supports id option while keeping display label" do
    schema =
      erd do
        u =
          table("users", id: :accounts) do
            pk :id, :uuid
          end

        k =
          table("api_keys") do
            pk :id, :uuid
            fk :account_id, :uuid
          end

        has_many u ~> k, "owns", from: :id, to: :account_id
      end

    assert schema.graph.nodes[:accounts].label == "users"
    assert [meta] = Map.values(schema.edge_meta)
    assert meta.cardinality == :one_to_many
    assert meta.label == "owns"
  end

  test "supports typed cardinality aliases and keyword edge forms" do
    schema =
      erd do
        users =
          table("users") do
            pk :id, :integer
          end

        profiles =
          table("profiles") do
            pk :id, :integer
            fk :user_id, :integer
          end

        roles =
          table("roles") do
            pk :id, :integer
          end

        memberships =
          table("memberships") do
            pk :id, :integer
            fk :user_id, :integer
            fk :role_id, :integer
          end

        has_one users ~> profiles, "has profile"
        edge users ~> memberships, one_to_many: "has membership"
        many_to_many users ~> roles, "can have roles"
      end

    metas = schema.edge_meta |> Map.values() |> Enum.sort_by(& &1.label)

    assert Enum.map(metas, & &1.cardinality) == [:many_to_many, :one_to_many, :one_to_one]
    assert Enum.map(metas, & &1.label) == ["can have roles", "has membership", "has profile"]
  end

  test "supports relationship pipe modifiers" do
    schema =
      erd do
        tenants =
          table("tenants") do
            pk :id, :uuid
          end

        users =
          table("users") do
            pk :id, :uuid
            fk :tenant_id, :uuid
          end

        tenants ~> users |> has_many("has users") |> columns(:id, :tenant_id)
      end

    assert [meta] = Map.values(schema.edge_meta)
    assert meta.cardinality == :one_to_many
    assert meta.label == "has users"
    assert meta.from_column == :id
    assert meta.to_column == :tenant_id
  end

  test "raises on unknown table variables" do
    assert_raise ArgumentError, ~r/unknown ERD table variable `posts`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.ERD

          erd do
            users =
              table("users") do
                pk :id, :integer
              end

            users ~> posts
          end
        end
      )
    end
  end

  test "raises on unsupported column declarations" do
    assert_raise ArgumentError, ~r/unsupported column declaration/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.ERD

          erd do
            table("users") do
              index(:email)
            end
          end
        end
      )
    end
  end

  defp edge_tuples(graph) do
    graph.edges
    |> Map.values()
    |> Enum.sort()
  end
end
