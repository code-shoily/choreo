defmodule Choreo.C4RenderCoverageTest do
  use ExUnit.Case, async: true

  alias Choreo.C4

  setup do
    model =
      C4.new()
      |> C4.add_person(:user, label: "User")
      |> C4.add_software_system(:banking, label: "Banking System", scope: :in)
      |> C4.add_container(:web_app, label: "Web App", technology: "Elixir", parent: :banking)
      |> C4.add_container(:db, label: "Database", technology: "Postgres", parent: :banking)
      |> C4.add_component(:auth, label: "Auth", technology: "Plug", parent: :web_app)
      |> C4.add_relationship(:user, :web_app, label: "Uses", technology: "HTTPS")
      |> C4.add_relationship(:web_app, :db, label: "Queries", technology: "SQL")
      |> C4.add_relationship(:auth, :db, label: "Validates")

    {:ok, model: model}
  end

  test "C4.Render.Mermaid themes and options", %{model: model} do
    for theme <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
      mermaid = C4.to_mermaid(model, theme: theme)
      assert mermaid =~ "graph LR"
      assert mermaid =~ "User"
      assert mermaid =~ "Banking System"
    end

    # Custom theme struct and overrides
    custom_theme = C4.Render.Mermaid.theme(:ocean, edge_color: "#123456")
    assert C4.to_mermaid(model, theme: custom_theme) =~ "#123456"

    # Virtual edge, highlighted nodes and edges
    virtual_model =
      model
      |> C4.add_relationship(:user, :db, label: "Virtual link")

    [edge_id] =
      for {id, meta} <- virtual_model.edge_meta, meta.label == "Virtual link", do: id

    virtual_model = put_in(virtual_model.edge_meta[edge_id][:edge_type], :virtual)

    mermaid_hl =
      C4.to_mermaid(virtual_model,
        highlighted_nodes: [:user],
        highlighted_edges: [{:web_app, :db}]
      )

    assert mermaid_hl =~ "Virtual link"
  end

  test "C4.Render.DOT themes and options", %{model: model} do
    for theme <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
      dot = C4.to_dot(model, theme: theme)
      assert dot =~ "digraph"
      assert dot =~ "User"
      assert dot =~ "Banking System"
    end

    # Custom theme struct and overrides
    custom_theme = C4.Render.DOT.theme(:warm, edge_color: "#654321")
    assert C4.to_dot(model, theme: custom_theme) =~ "#654321"

    # Virtual edge, highlighted nodes and edges
    virtual_model =
      model
      |> C4.add_relationship(:user, :db, label: "Virtual link")

    [edge_id] =
      for {id, meta} <- virtual_model.edge_meta, meta.label == "Virtual link", do: id

    virtual_model = put_in(virtual_model.edge_meta[edge_id][:edge_type], :virtual)

    dot_hl =
      C4.to_dot(virtual_model,
        highlighted_nodes: [:user],
        highlighted_edges: [{:web_app, :db}]
      )

    assert dot_hl =~ "style=\"dashed\""
    assert dot_hl =~ "color=\"#cbd5e1\""

    # Fallback theme and node attribute overrides
    assert C4.to_dot(model, theme: :unknown_theme) =~ "digraph"

    custom_node_model =
      C4.new()
      |> C4.add_software_system(:custom_sys,
        label: "Custom",
        description: "A custom system tooltip",
        shape: :hexagon,
        fillcolor: "#abcdef",
        fontcolor: "#123456",
        style: "dotted",
        penwidth: 3.5,
        image: "icon.png"
      )
      |> C4.add_relationship(:custom_sys, :custom_sys, label: "", technology: "")

    custom_dot = C4.to_dot(custom_node_model)
    assert custom_dot =~ "tooltip=\"A custom system tooltip\""
    assert custom_dot =~ "shape=\"hexagon\""
    assert custom_dot =~ "fillcolor=\"#abcdef\""
    assert custom_dot =~ "fontcolor=\"#123456\""
    assert custom_dot =~ "image=\"icon.png\""
  end
end
