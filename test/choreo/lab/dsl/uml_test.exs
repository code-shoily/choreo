defmodule Choreo.Lab.UMLDSLTest do
  use ExUnit.Case, async: true

  alias Choreo.Lab.DSL.UML, as: DSL
  import Choreo.Lab.DSL.UML

  doctest Choreo.Lab.DSL.UML

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = DSL.taxonomy()

    assert :class in taxonomy.nodes
    assert :struct in taxonomy.nodes
    assert :protocol in taxonomy.nodes
    assert :field in taxonomy.members
    assert :function in taxonomy.members
    assert :implements in taxonomy.edges
    assert :depends in taxonomy.modifiers
    assert :type in taxonomy.modifiers
    assert :visibility in taxonomy.options
    assert DSL.verbs() == taxonomy
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

  test "supports edge/3 with label and options" do
    diagram =
      uml do
        controller = class("Controller")
        repo = class("Repo")

        edge(controller ~> repo, "calls", type: :depends)
      end

    assert [meta] = Map.values(diagram.edge_meta)
    assert meta.type == :depends
    assert meta.label == "calls"
  end

  test "supports piped modifiers with options and type/1,2 modifiers" do
    diagram =
      uml do
        controller = class("Controller")
        repo = class("Repo")
        behaviour = behavior("RepoBehaviour")
        cache = interface("Cache")

        controller ~> repo |> depends(label: "calls")
        repo ~> behaviour |> type(:realizes, "implements")
        controller ~> cache |> type(:associates)
      end

    metas = diagram.edge_meta |> Map.values() |> Enum.sort_by(&Map.get(&1, :label, ""))

    assert Enum.map(metas, & &1.type) == [:associates, :depends, :realizes]
    assert Enum.map(metas, &Map.get(&1, :label)) == [nil, "calls", "implements"]
  end

  test "supports standalone class declaration inside DSL" do
    diagram =
      uml do
        interface "Cache" do
          function :get, 1
        end
      end

    assert Map.has_key?(diagram.graph.nodes, :cache)
    assert diagram.graph.nodes[:cache].type == :interface

    assert Enum.map(diagram.graph.nodes[:cache].functions, &Map.new/1) == [
             %{name: "get", arity: 1, visibility: :public}
           ]
  end

  test "forwards options like strict_contract_validation to UML diagram" do
    assert_raise ArgumentError, ~r/contract violation/, fn ->
      uml strict_contract_validation: true do
        auth =
          behavior("AuthProvider") do
            function(:verify, 1)
          end

        user = struct("User")

        realizes(user ~> auth)
      end
    end

    diagram =
      uml strict_contract_validation: true do
        auth =
          behavior("AuthProvider") do
            function(:verify, 1)
          end

        user =
          struct("User") do
            function(:verify, 1)
          end

        realizes(user ~> auth)
      end

    assert [meta] = Map.values(diagram.edge_meta)
    assert meta.type == :realizes
  end

  test "autocomplete stubs raise outside DSL block" do
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn -> DSL.class() end
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn -> DSL.edge() end
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn -> DSL.type() end
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn -> DSL.on() end
  end

  test "supports typed relationship statement with label and options" do
    diagram =
      uml do
        c = class("Client")
        s = class("Server")

        depends c ~> s, "requests"
      end

    assert [meta] = Map.values(diagram.edge_meta)
    assert meta.type == :depends
    assert meta.label == "requests"
  end

  test "raises on unsupported statement" do
    assert_raise ArgumentError, ~r/unsupported statement in UML DSL/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.UML

          uml do
            unknown_func()
          end
        end
      )
    end
  end

  test "raises on unsupported assignment constructor" do
    assert_raise ArgumentError, ~r/expected UML class constructor/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.UML

          uml do
            x = 1 + 2
          end
        end
      )
    end
  end

  test "raises on invalid relationship AST" do
    assert_raise ArgumentError, ~r/expected `from ~> to` in UML DSL/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.UML

          uml do
            edge :invalid_arrow
          end
        end
      )
    end
  end

  test "raises on unknown class variable" do
    assert_raise ArgumentError, ~r/unknown UML class variable `missing`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.UML

          uml do
            c = class("Client")
            c ~> missing
          end
        end
      )
    end
  end

  test "raises on unsupported relationship modifier" do
    assert_raise ArgumentError, ~r/unsupported UML relationship modifier/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.UML

          uml do
            c = class("Client")
            s = class("Server")
            c ~> s |> bad_modifier()
          end
        end
      )
    end
  end
end
