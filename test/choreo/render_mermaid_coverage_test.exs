defmodule Choreo.RenderMermaidCoverageTest do
  use ExUnit.Case, async: true

  alias Choreo
  alias Choreo.Render.Mermaid

  test "to_mermaid_shape/1 covers all supported shapes" do
    assert Mermaid.to_mermaid_shape(:cylinder) == :cylinder
    assert Mermaid.to_mermaid_shape(:octagon) == :hexagon
    assert Mermaid.to_mermaid_shape(:box3d) == :subroutine
    assert Mermaid.to_mermaid_shape(:cloud) == :rounded_rect
    assert Mermaid.to_mermaid_shape(:doublecircle) == :circle
    assert Mermaid.to_mermaid_shape(:hexagon) == :hexagon
    assert Mermaid.to_mermaid_shape(:component) == :stadium
    assert Mermaid.to_mermaid_shape(:tab) == :rounded_rect
    assert Mermaid.to_mermaid_shape(:box) == :rounded_rect
    assert Mermaid.to_mermaid_shape(:ellipse) == :rounded_rect
    assert Mermaid.to_mermaid_shape(:circle) == :circle
    assert Mermaid.to_mermaid_shape(:diamond) == :rhombus
    assert Mermaid.to_mermaid_shape(:unknown_shape) == :rounded_rect
  end

  test "native_token/2 with fallback" do
    assert Mermaid.native_token("valid_token") == "valid_token"
    assert Mermaid.native_token("", "fallback") == "fallback"
    assert Mermaid.native_token("!@#$%", "fallback") == "fallback"
  end

  test "native_label/1 sanitization" do
    assert Mermaid.native_label("line 1\nline 2") == "line 1 line 2"

    assert Mermaid.native_label("with \"quotes\" | pipe \\ slash") ==
             "with 'quotes' / pipe / slash"
  end

  test "Mermaid rendering themes, fields, and edge types" do
    system =
      Choreo.new()
      |> Choreo.add_service(:api,
        label: "API",
        penwidth: 2.0,
        description: "Main API"
      )
      |> Choreo.add_database(:db, label: "DB", fillcolor: "#fffffe")
      |> Choreo.add_cache(:cache, label: "Cache", fillcolor: "#111111")
      |> Choreo.connect(:api, :db, protocol: :grpc)
      |> Choreo.connect(:api, :cache, type: :dataflow)
      |> Choreo.connect(:cache, :db, type: :sync)

    [edge1, edge2 | _] = Map.keys(system.edge_meta)

    system =
      system
      |> put_in([Access.key(:edge_meta), edge1, :edge_type], :virtual)
      |> put_in([Access.key(:edge_meta), edge2, :edge_type], :trace)

    # Attach fields to node data to exercise node_label/2 field formatting
    api_data = Yog.Multi.node(system.graph, :api)

    updated_data =
      Map.put(api_data, :fields, [{"status", ["pending", "active", "done"]}, {"retries", 3}])

    system = %{system | graph: Yog.Multi.add_node(system.graph, :api, updated_data)}

    for theme <- [:warm, :forest, :ocean, :minimal, :dark, :default] do
      mermaid = Choreo.to_mermaid(system, theme: theme)
      assert mermaid =~ "graph TD"
      assert mermaid =~ "API"
      assert mermaid =~ "pending | active | done"
      assert mermaid =~ "retries: 3"
    end
  end
end
