defmodule Choreo.Lab.UMLDSLTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.UML

  doctest Choreo.Lab.DSL.UML

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.UML.taxonomy()

    assert :class in taxonomy.nodes
    assert :struct in taxonomy.nodes
    assert :protocol in taxonomy.nodes
    assert :field in taxonomy.members
    assert :function in taxonomy.members
    assert :implements in taxonomy.edges
    assert :depends in taxonomy.modifiers
    assert :visibility in taxonomy.options
    assert Choreo.Lab.DSL.UML.verbs() == taxonomy
  end

  test "builds a UML diagram with block-based class declarations" do
    diagram =
      uml do
        user =
          struct("User") do
            field :id, :integer
            private(field(:email, :string))
            function :authenticate, 2, return: :boolean
          end

        auth =
          behavior("AuthProvider") do
            function :verify, 1, return: :ok_error
          end

        realizes user ~> auth, "implements"
      end

    assert diagram.graph.nodes[:user].type == :struct
    assert diagram.graph.nodes[:user].label == "User"

    assert Enum.map(diagram.graph.nodes[:user].fields, &Map.new/1) == [
             %{name: "id", type: :integer, visibility: :public},
             %{name: "email", type: :string, visibility: :private}
           ]

    assert Enum.map(diagram.graph.nodes[:user].functions, &Map.new/1) == [
             %{name: "authenticate", arity: 2, return: :boolean, visibility: :public}
           ]

    assert diagram.graph.nodes[:auth].type == :behavior
    assert [meta] = Map.values(diagram.edge_meta)
    assert meta.type == :realizes
    assert meta.label == "implements"
  end

  test "supports inline constructors for one-off sketches" do
    diagram =
      uml do
        class("Controller") ~> class("Repo") |> depends("calls")
      end

    assert Map.has_key?(diagram.graph.nodes, :controller)
    assert Map.has_key?(diagram.graph.nodes, :repo)
    assert [meta] = Map.values(diagram.edge_meta)
    assert meta.type == :depends
    assert meta.label == "calls"
  end

  test "supports id option while keeping display label" do
    diagram =
      uml do
        impl =
          struct("PostgresRepo", id: :repo) do
            function :get, 1
          end

        contract =
          protocol("Repository") do
            function :get, 1
          end

        implements impl ~> contract, "satisfies"
      end

    assert diagram.graph.nodes[:repo].label == "PostgresRepo"
    assert [meta] = Map.values(diagram.edge_meta)
    assert meta.type == :realizes
    assert meta.label == "satisfies"
  end

  test "supports typed relationship aliases and keyword edge forms" do
    diagram =
      uml do
        base = class("Base")
        child = class("Child")
        service = class("Service")
        repo = class("Repo")
        profile = struct("Profile")

        extends child ~> base, "inherits behavior"
        edge service ~> repo, uses: "queries"
        has service ~> profile, "owns"
      end

    metas = diagram.edge_meta |> Map.values() |> Enum.sort_by(& &1.label)

    assert Enum.map(metas, & &1.type) == [:inherits, :associates, :depends]
    assert Enum.map(metas, & &1.label) == ["inherits behavior", "owns", "queries"]
  end

  test "supports relationship pipe modifiers" do
    diagram =
      uml do
        controller = class("Controller")
        repo = class("Repo")
        behaviour = behavior("RepoBehaviour")

        controller ~> repo |> depends("calls")
        repo ~> behaviour |> implements("contract")
      end

    metas = diagram.edge_meta |> Map.values() |> Enum.sort_by(& &1.label)

    assert Enum.map(metas, & &1.type) == [:depends, :realizes]
    assert Enum.map(metas, & &1.label) == ["calls", "contract"]
  end

  test "supports protected and public visibility wrappers" do
    diagram =
      uml do
        service =
          class("Service") do
            protected(field(:state, :map))
            public(method(:call, 1, return: :ok))
          end
      end

    assert Enum.map(diagram.graph.nodes[:service].fields, &Map.new/1) == [
             %{name: "state", type: :map, visibility: :protected}
           ]

    assert Enum.map(diagram.graph.nodes[:service].functions, &Map.new/1) == [
             %{name: "call", arity: 1, return: :ok, visibility: :public}
           ]
  end

  test "raises on unknown class variables" do
    assert_raise ArgumentError, ~r/unknown UML class variable `repo`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.UML

          uml do
            service = class("Service")
            service ~> repo
          end
        end
      )
    end
  end

  test "raises on unsupported member declarations" do
    assert_raise ArgumentError, ~r/unsupported member declaration/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.UML

          uml do
            class("Service") do
              callback(:call, 1)
            end
          end
        end
      )
    end
  end
end
