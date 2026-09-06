defmodule Choreo.Lab.ERDDSLTest do
  use ExUnit.Case, async: true

  alias Choreo.Lab.DSL.ERD, as: DSL
  import Choreo.Lab.DSL.ERD

  doctest Choreo.Lab.DSL.ERD

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = DSL.taxonomy()

    assert :table in taxonomy.tables
    assert :entity in taxonomy.tables
    assert :pk in taxonomy.columns
    assert :fk in taxonomy.columns
    assert :one_to_many in taxonomy.edges
    assert :has_many in taxonomy.edges
    assert :columns in taxonomy.modifiers
    assert :from_column in taxonomy.options
    assert DSL.verbs() == taxonomy
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

  test "supports edge with label and keyword options" do
    schema =
      erd do
        users =
          table("users") do
            pk :id, :integer
          end

        posts =
          table("posts") do
            pk :id, :integer
            fk :user_id, :integer
          end

        edge(users ~> posts, "writes", from: :id, to: :user_id, cardinality: :one_to_many)
      end

    assert [meta] = Map.values(schema.edge_meta)
    assert meta.label == "writes"
    assert meta.from_column == :id
    assert meta.to_column == :user_id
    assert meta.cardinality == :one_to_many
  end

  test "supports relationship pipe modifiers with options and cardinality helper" do
    schema =
      erd do
        users =
          table("users") do
            pk :id, :integer
          end

        posts =
          table("posts") do
            pk :id, :integer
            fk :user_id, :integer
          end

        tags =
          table("tags") do
            pk :id, :integer
          end

        posts_tags =
          table("posts_tags") do
            pk :post_id, :integer
            pk :tag_id, :integer
          end

        users ~> posts |> one_to_many("writes", from: :id, to: :user_id)

        posts
        ~> posts_tags
        |> from_column(:id)
        |> to_column(:post_id)
        |> cardinality(:one_to_many)

        tags ~> posts_tags |> has_many(from: :id, to: :tag_id)
      end

    assert map_size(schema.edge_meta) == 3
  end

  test "supports strict and strict_column_matching options" do
    assert_raise ArgumentError, ~r/strict_column_matching is enabled/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.ERD

          erd strict_column_matching: true do
            users =
              table("users") do
                pk :id, :integer
              end

            posts =
              table("posts") do
                fk :user_id, :integer
              end

            one_to_many users ~> posts
          end
        end
      )
    end

    assert_raise ArgumentError, ~r/type mismatch/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.ERD

          erd do
            users =
              table("users") do
                pk :id, :integer
              end

            posts =
              table("posts") do
                fk :user_uuid, :varchar
              end

            one_to_many users ~> posts, from: :id, to: :user_uuid
          end
        end
      )
    end
  end

  test "supports unassigned table and entity constructors with various column verbs" do
    schema =
      erd do
        entity "tenants" do
          primary_key :id, :uuid
          column :name, :string
        end

        table :audit_logs do
          pk :id, :integer
          foreign_key :tenant_id, :uuid
          field :event, :varchar, comment: "audit event"
        end
      end

    assert Map.has_key?(schema.graph.nodes, :tenants)
    assert Map.has_key?(schema.graph.nodes, :audit_logs)
    audit_cols = schema.graph.nodes[:audit_logs].columns
    assert Enum.map(audit_cols, & &1[:name]) == [:id, :tenant_id, :event]
  end

  test "autocomplete stubs raise outside DSL block" do
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      DSL.table()
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      DSL.pk()
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      DSL.edge()
    end
  end

  test "supports all relationship macros without options and bare edge" do
    schema =
      erd do
        a = table("a")
        b = table("b")
        c = table("c")
        d = table("d")
        e = table("e")
        f = table("f")

        a ~> b
        edge a ~> c
        edge a ~> d, "links"
        maybe_has_many a ~> e
        has_at_least_one a ~> f
        has_and_belongs_to_many e ~> f
      end

    assert map_size(schema.edge_meta) == 6
  end

  test "raises on unsupported modifier" do
    assert_raise ArgumentError, ~r/unsupported ERD relationship modifier/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.ERD

          erd do
            users = table("users")
            posts = table("posts")
            users ~> posts |> invalid_modifier("foo")
          end
        end
      )
    end
  end

  test "raises on unsupported statement" do
    assert_raise ArgumentError, ~r/unsupported statement in ERD DSL/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.ERD

          erd do
            123
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
