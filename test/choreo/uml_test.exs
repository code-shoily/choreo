defmodule Choreo.UMLTest do
  use ExUnit.Case, async: true

  alias Choreo.UML
  doctest Choreo.UML

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

  test "add_relationship implicitly registers missing classes and validates type options" do
    uml =
      UML.new()
      |> UML.add_class(:a)
      |> UML.add_relationship(:a, :b, type: :inherits)

    assert Map.has_key?(uml.graph.nodes, :b)
    assert Map.get(uml.graph.nodes, :b).type == :class
    assert Map.get(uml.graph.nodes, :b).label == "b"

    assert_raise NimbleOptions.ValidationError, fn ->
      UML.add_relationship(uml, :a, :b, type: :invalid)
    end
  end

  test "strict mode raises when relationship endpoint is missing" do
    assert_raise ArgumentError, ~r/Source class :a does not exist/, fn ->
      UML.new(strict: true)
      |> UML.add_class(:b)
      |> UML.add_relationship(:a, :b, type: :depends)
    end

    assert_raise ArgumentError, ~r/Target class :b does not exist/, fn ->
      UML.new(strict: true)
      |> UML.add_class(:a)
      |> UML.add_relationship(:a, :b, type: :depends)
    end
  end

  test "add_relationship auto-creates missing classes" do
    uml =
      UML.new()
      |> UML.add_relationship(:a, :b, type: :depends)

    assert Map.has_key?(uml.graph.nodes, :a)
    assert Map.has_key?(uml.graph.nodes, :b)
  end

  test "add_class validates fields and functions are lists" do
    assert_raise ArgumentError, ~r/expected :fields to be a list/, fn ->
      UML.new() |> UML.add_class(:a, fields: "not_a_list")
    end

    assert_raise ArgumentError, ~r/expected :functions to be a list/, fn ->
      UML.new() |> UML.add_class(:a, functions: "not_a_list")
    end
  end

  test "add_relationship strict_contract_validation checks" do
    # When strict_contract_validation is true, realizing a behavior must implement all functions
    uml_strict =
      UML.new(strict_contract_validation: true)
      |> UML.add_class(:auth_behavior,
        type: :behavior,
        functions: [
          %{name: "verify", arity: 1},
          %{name: "cleanup", arity: 0}
        ]
      )
      |> UML.add_class(:provider,
        type: :struct,
        functions: [
          %{name: "verify", arity: 1}
        ]
      )

    # Should raise contract violation because cleanup/0 is missing
    assert_raise ArgumentError, ~r/contract violation.*cleanup\/0/, fn ->
      UML.add_relationship(uml_strict, :provider, :auth_behavior, type: :realizes)
    end

    # Should pass when all functions are implemented
    uml_ok =
      UML.new(strict_contract_validation: true)
      |> UML.add_class(:auth_behavior,
        type: :behavior,
        functions: [
          %{name: "verify", arity: 1}
        ]
      )
      |> UML.add_class(:provider,
        type: :struct,
        functions: [
          %{name: "verify", arity: 1}
        ]
      )
      |> UML.add_relationship(:provider, :auth_behavior, type: :realizes)

    assert %UML{} = uml_ok
  end

  test "to_dot rendering with 3-compartment HTML table", %{uml: uml} do
    dot = UML.to_dot(uml)

    # Compartments check
    assert dot =~ "label=<<TABLE"
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
      assert UML.to_dot(uml, theme: theme) =~ "label=<<TABLE"
    end
  end

  test "to_dot highlighting", %{uml: uml} do
    dot = UML.to_dot(uml, highlighted_nodes: [:user], highlighted_edges: [0])
    assert dot =~ "user [label=<<TABLE"
    assert dot =~ "color=\"#ef4444\""
  end

  test "to_dot highlights edges by tuple", %{uml: uml} do
    dot = UML.to_dot(uml, highlighted_edges: [{:user, :auth_provider}])
    assert dot =~ "user"
    assert dot =~ "auth_provider"
  end

  test "to_dot renders all relationship types" do
    uml =
      UML.new()
      |> UML.add_class(:a)
      |> UML.add_class(:b)
      |> UML.add_class(:c)
      |> UML.add_class(:d)
      |> UML.add_relationship(:a, :b, type: :inherits)
      |> UML.add_relationship(:a, :c, type: :associates)
      |> UML.add_relationship(:a, :d, type: :depends)

    dot = UML.to_dot(uml)
    assert dot =~ "style=\"dashed\""
    assert dot =~ "arrowhead=\"empty\""
  end

  test "to_dot supports custom and fallback themes" do
    uml = UML.new() |> UML.add_class(:a)

    custom =
      Choreo.Theme.custom(
        colors: %{
          class: "#ff0000",
          header_fg: "#ffffff",
          text_color: "#1e293b",
          border_color: "#cbd5e1",
          bg_color: "#f8fafc"
        },
        node_fontcolor: "white"
      )

    assert UML.to_dot(uml, theme: custom) =~ "#ff0000"
    assert UML.to_dot(uml, theme: :unknown_theme) =~ "label=<<TABLE"
  end

  test "to_dot renders protected visibility" do
    uml =
      UML.new()
      |> UML.add_class(:a,
        fields: [%{name: :secret, type: :string, visibility: :protected}],
        functions: [%{name: "hidden", arity: 0, visibility: :protected}]
      )

    dot = UML.to_dot(uml)
    assert dot =~ "#"
  end

  test "render via Choreo protocol delegations", %{uml: uml} do
    assert Choreo.to_dot(uml) =~ "digraph"
    assert Choreo.to_mermaid(uml) =~ "graph TD"
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
    assert mermaid =~ "class user {"
    assert mermaid =~ "<<struct>>"
    assert mermaid =~ "+id integer"
    assert mermaid =~ "-email string"
    assert mermaid =~ "+authenticate(2) boolean"
    assert mermaid =~ "user ..|> auth_provider : implements"
  end

  test "to_mermaid flowchart supports directions" do
    uml =
      UML.new()
      |> UML.add_class(:a)
      |> UML.add_class(:b)
      |> UML.add_relationship(:a, :b, type: :depends)

    assert UML.to_mermaid(uml, syntax: :flowchart, direction: :td) =~ "graph TD"
    assert UML.to_mermaid(uml, syntax: :flowchart, direction: :lr) =~ "graph LR"
  end

  test "to_mermaid renders all relationship types" do
    uml =
      UML.new()
      |> UML.add_class(:a)
      |> UML.add_class(:b)
      |> UML.add_class(:c)
      |> UML.add_class(:d)
      |> UML.add_relationship(:a, :b, type: :inherits)
      |> UML.add_relationship(:a, :c, type: :associates)
      |> UML.add_relationship(:a, :d, type: :depends)

    mermaid = UML.to_mermaid(uml, syntax: :class_diagram)
    assert mermaid =~ "--|>"
    assert mermaid =~ "-->"
    assert mermaid =~ "..>"
  end

  test "zoom levels filter classes by type" do
    uml =
      UML.new()
      |> UML.add_class(:service, type: :class)
      |> UML.add_class(:auth, type: :behavior)
      |> UML.add_class(:repo, type: :class)
      |> UML.add_relationship(:service, :auth, type: :realizes)

    zoom_0 = Choreo.View.zoom(uml, level: 0)
    assert :auth in Map.keys(zoom_0.graph.nodes)
    refute :service in Map.keys(zoom_0.graph.nodes)

    zoom_2 = Choreo.View.zoom(uml, level: 2)
    assert :service in Map.keys(zoom_2.graph.nodes)
    assert :auth in Map.keys(zoom_2.graph.nodes)
    assert :repo in Map.keys(zoom_2.graph.nodes)
  end

  test "viewable protocol implementation", %{uml: uml} do
    assert is_function(Choreo.Viewable.zoom_predicate(uml, 1))
    assert %{type: :depends, label: nil} = Choreo.Viewable.virtual_edge_meta(uml)

    rebuilt = Choreo.Viewable.rebuild(uml, uml.graph)
    assert rebuilt.graph == uml.graph
    assert rebuilt.edge_meta == uml.edge_meta
  end

  describe "hardened edge cases" do
    test "to_dot/2 handles class names with spaces and special characters" do
      uml =
        UML.new()
        |> UML.add_class("my class")
        |> UML.add_class("another-class!")
        |> UML.add_relationship("my class", "another-class!", type: :inherits)

      dot = UML.to_dot(uml)
      assert String.contains?(dot, "\"my class\"")
      assert String.contains?(dot, "\"another-class!\"")
    end

    test "to_mermaid/2 handles class names with spaces and special characters" do
      uml =
        UML.new()
        |> UML.add_class("my class")
        |> UML.add_class("another-class!")
        |> UML.add_relationship("my class", "another-class!", type: :inherits)

      mermaid = UML.to_mermaid(uml)
      assert String.contains?(mermaid, "my class")
      assert String.contains?(mermaid, "another-class!")
    end
  end
end
