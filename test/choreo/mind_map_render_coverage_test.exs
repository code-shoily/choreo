defmodule Choreo.MindMapRenderCoverageTest do
  use ExUnit.Case, async: true

  alias Choreo.MindMap
  alias Choreo.MindMap.Render.DOT
  alias Choreo.MindMap.Render.Mermaid

  setup do
    map =
      MindMap.new()
      |> MindMap.set_root(:root, label: "Central Theme")
      |> MindMap.add_topic(:t1, label: "Topic 1")
      |> MindMap.add_topic(:t2, label: "Topic 2")
      |> MindMap.add_subtopic(:s1, label: "Subtopic 1")
      |> MindMap.add_note(:n1, label: "Important Note")
      |> MindMap.branch(:root, :t1)
      |> MindMap.branch(:root, :t2)
      |> MindMap.branch(:t1, :s1)
      |> MindMap.branch(:t2, :n1)
      |> MindMap.associate(:s1, :n1, label: "Related")

    {:ok, map: map}
  end

  describe "DOT rendering" do
    test "renders all themes and overrides", %{map: map} do
      for theme_name <- [:default, :dark, :minimal, :warm, :forest, :ocean] do
        dot = DOT.to_dot(map, theme: theme_name)
        assert dot =~ "digraph"
        assert dot =~ "Central Theme"
      end

      # Custom theme and overrides
      theme = DOT.theme(:warm, edge_color: "#123456")
      dot = DOT.to_dot(map, theme: theme)
      assert dot =~ "#123456"

      # Fallback theme
      fallback_dot = DOT.to_dot(map, theme: :non_existent)
      assert fallback_dot =~ "digraph"
    end

    test "renders with highlighted nodes and edges", %{map: map} do
      dot =
        DOT.to_dot(map,
          highlighted_nodes: [:root, :s1],
          highlighted_edges: [{:root, :t1}],
          rankdir: :lr
        )

      assert dot =~ "digraph"
      assert dot =~ "rankdir=LR"
    end
  end

  describe "Mermaid rendering" do
    test "renders flowchart syntax across themes", %{map: map} do
      for theme_name <- [:default, :dark, :minimal, :warm, :forest, :ocean] do
        out = Mermaid.to_mermaid(map, syntax: :flowchart, theme: theme_name)
        assert out =~ "graph TD"
      end

      # Custom theme
      theme = Mermaid.theme(:ocean, colors: %{root: "#abcdef"})
      out = Mermaid.to_mermaid(map, theme: theme)
      assert out =~ "#abcdef"

      # Unknown theme fallback
      assert Mermaid.to_mermaid(map, theme: :unknown) =~ "graph TD"
    end

    test "renders native mindmap and ishikawa syntaxes", %{map: map} do
      mindmap_out = Mermaid.to_mermaid(map, syntax: :mindmap)
      assert mindmap_out =~ "mindmap"
      assert mindmap_out =~ "Central Theme"

      ishikawa_out = Mermaid.to_mermaid(map, syntax: :ishikawa)
      assert ishikawa_out =~ "ishikawa"
      assert ishikawa_out =~ "Central Theme"
    end

    test "raises on native hierarchy when root is missing or cyclic" do
      no_root = MindMap.new()

      assert_raise ArgumentError, ~r/MindMap must have a root set/, fn ->
        Mermaid.to_mermaid(no_root, syntax: :mindmap)
      end

      cyclic =
        MindMap.new()
        |> MindMap.set_root(:r)
        |> MindMap.add_topic(:a)
        |> MindMap.branch(:r, :a)
        |> MindMap.branch(:a, :r)

      assert_raise ArgumentError, ~r/MindMap contains a cycle/, fn ->
        Mermaid.to_mermaid(cyclic, syntax: :ishikawa)
      end
    end
  end
end
