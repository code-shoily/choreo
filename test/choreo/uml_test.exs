defmodule Choreo.UMLTest do
  use ExUnit.Case, async: true

  alias Choreo.UML

  setup do
    uml =
      UML.new()
      |> UML.add_class(:user,
        type: :struct,
        label: "User Model",
        fields: [
          %{name: :id, type: :integer, visibility: :public},
          %{name: :email, type: :string, visibility: :private}
        ],
        functions: [
          %{name: "authenticate", arity: 2, return: :boolean, visibility: :public}
        ]
      )
      |> UML.add_class(:auth_provider,
        type: :behavior,
        functions: [
          %{name: "verify", arity: 1, return: :ok_error, visibility: :public}
        ]
      )
      |> UML.add_relationship(:user, :auth_provider, type: :realizes, label: "implements")

    {:ok, uml: uml}
  end

  test "initializes empty UML diagram" do
    uml = UML.new()
    assert %UML{} = uml
    assert uml.graph.nodes == %{}
  end

  test "add_class validates fields and functions" do
    assert_raise NimbleOptions.ValidationError, fn ->
      UML.new() |> UML.add_class(:invalid, fields: [%{type: :integer}])
    end

    assert_raise ArgumentError, fn ->
      UML.new() |> UML.add_class(:invalid, fields: "not_a_list")
    end
  end

  test "add_relationship validates existing nodes and type options" do
    uml = UML.new() |> UML.add_class(:a)

    assert_raise ArgumentError, ~r/does not exist/, fn ->
      UML.add_relationship(uml, :a, :b, type: :inherits)
    end

    assert_raise NimbleOptions.ValidationError, fn ->
      uml = UML.add_class(uml, :b)
      UML.add_relationship(uml, :a, :b, type: :invalid)
    end
  end

  test "to_dot rendering with 3-compartment HTML table", %{uml: uml} do
    dot = UML.to_dot(uml)

    # Compartments check
    assert dot =~ "label=<TABLE"
    assert dot =~ "User Model"
    assert dot =~ "«struct»"
    assert dot =~ "auth_provider"
    assert dot =~ "«behavior»"

    # Visibility symbols
    assert dot =~ "+ id : integer"
    assert dot =~ "- email : string"
    assert dot =~ "+ authenticate(2) : boolean"

    # Line styling for realizing/implementing
    assert dot =~ "style=\"dashed\""
    assert dot =~ "arrowhead=\"empty\""
  end

  test "to_dot custom themes", %{uml: uml} do
    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert UML.to_dot(uml, theme: theme) =~ "label=<TABLE"
    end
  end

  test "to_dot highlighting", %{uml: uml} do
    dot = UML.to_dot(uml, highlighted_nodes: [:user], highlighted_edges: [0])
    assert dot =~ "user [label=<TABLE"
    assert dot =~ "color=\"#ef4444\""
  end

  test "to_mermaid flowchart rendering", %{uml: uml} do
    mermaid = UML.to_mermaid(uml, syntax: :flowchart)

    assert mermaid =~ "graph TD"
    assert mermaid =~ "User Model"
    assert mermaid =~ "«struct»"
    assert mermaid =~ "authenticate"
  end

  test "to_mermaid native classDiagram rendering", %{uml: uml} do
    mermaid = UML.to_mermaid(uml, syntax: :class_diagram)

    assert mermaid =~ "classDiagram"
    assert mermaid =~ "class user[\"User Model\"] {"
    assert mermaid =~ "<<struct>>"
    assert mermaid =~ "+id integer"
    assert mermaid =~ "-email string"
    assert mermaid =~ "+authenticate(2) boolean"
    assert mermaid =~ "user ..|> auth_provider : implements"
  end

  test "viewable protocol implementation", %{uml: uml} do
    assert Choreo.Viewable.zoom_predicate(uml, 1) != nil
    assert Choreo.Viewable.virtual_edge_meta(uml) != nil

    rebuilt = Choreo.Viewable.rebuild(uml, uml.graph)
    assert rebuilt.graph == uml.graph
    assert rebuilt.edge_meta == uml.edge_meta
  end
end
