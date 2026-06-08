defmodule Choreo.MindMap.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.MindMap` diagrams.

  Produces mind-map-oriented visualisation:

    * **Root** — circle with thick stroke (central concept)
    * **Topics** — rounded rectangles (main branches)
    * **Subtopics** — boxes (nested ideas)
    * **Notes** — rounded rectangles with distinct colour (annotations)

  Edge styles:
    * **Branch** — solid grey (hierarchical connection)
    * **Associates** — dashed grey, bidirectional (cross-link)
    * **Virtual** — dashed light grey (zoom-level transitive links)

  ## Further reading

    * [Mind Map (Wikipedia)](https://en.wikipedia.org/wiki/Mind_map)
  """

  alias Choreo.Theme

  @doc """
  Renders a mind map to a Mermaid flowchart string.

  ## Options

    * `:syntax` — `:flowchart` (default) or `:mindmap`
    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:td` (default), `:lr`, `:bt`, `:rl`
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of `{from, to}` tuples to highlight
    * Any other option accepted by `Yog.Multi.Mermaid.to_mermaid/2`

  ## Native `:mindmap` syntax limitations

  Mermaid's `mindmap` syntax is purely hierarchical — it cannot represent
  associative (cross-link) edges. When `:syntax` is `:mindmap`:

    * associative edges are silently omitted
    * nodes with multiple branch parents are duplicated under each parent
    * cycles will cause an infinite loop (use `Analysis.cyclic?/1` first)

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:ideas, label: "Ideas")
      ...>   |> Choreo.MindMap.add_topic(:topic_a, label: "Topic A")
      ...>   |> Choreo.MindMap.add_subtopic(:sub_a, label: "Sub A")
      ...>   |> Choreo.MindMap.branch(:ideas, :topic_a)
      ...>   |> Choreo.MindMap.branch(:topic_a, :sub_a)
      iex> mermaid = Choreo.MindMap.Render.Mermaid.to_mermaid(map)
      iex> String.contains?(mermaid, "graph TD")
      true
      iex> String.contains?(mermaid, "Ideas")
      true
      iex> String.contains?(mermaid, "Topic A")
      true
  """
  @spec to_mermaid(Choreo.MindMap.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.MindMap{} = map, opts \\ []) do
    case Keyword.get(opts, :syntax, :flowchart) do
      :mindmap ->
        to_native_mindmap(map)

      :flowchart ->
        theme = resolve_theme(Keyword.get(opts, :theme, :default))
        direction = Keyword.get(opts, :direction, :td)

        {multi_graph, edge_id_map} = Choreo.Internal.to_multi_graph(map.graph)

        # Build edge_meta keyed by edge_id for the multigraph renderer
        multi_edge_meta =
          Map.new(edge_id_map, fn {edge_id, {from, to}} ->
            meta = Map.get(map.edge_meta, {from, to}, %{})
            {edge_id, meta}
          end)

        virtual_map = %{graph: multi_graph, edge_meta: multi_edge_meta}

        hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
        hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

        base =
          Yog.Multi.Mermaid.default_options()
          |> Map.put(:node_label, &node_label/2)
          |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(virtual_map, edge_id) end)
          |> Map.put(:node_shape, &node_shape_fn/2)
          |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
          |> Map.put(:edge_attributes, edge_attributes_fn(virtual_map, hl_edges))
          |> Map.put(:direction, direction)
          |> Map.put(:default_font_color, theme.node_fontcolor)
          |> Map.merge(Map.new(opts))

        Yog.Multi.Mermaid.to_mermaid(multi_graph, base)
        |> String.replace("stroke_dasharray", "stroke-dasharray")
    end
  end

  defp to_native_mindmap(map) do
    if is_nil(map.root) do
      raise ArgumentError, "MindMap must have a root set to be rendered"
    end

    if Choreo.MindMap.Analysis.cyclic?(map) do
      raise ArgumentError,
            "MindMap contains a cycle and cannot be rendered with :mindmap syntax"
    end

    "mindmap\n" <> render_mindmap_node(map, map.root, 0, MapSet.new([map.root])) <> "\n"
  end

  defp render_mindmap_node(map, node_id, depth, visited) do
    data = Map.get(map.graph.nodes, node_id, %{})
    label = data[:label] || to_string(node_id)

    indent = String.duplicate("  ", depth)
    safe_label = sanitize_mindmap_label(label)
    line = "#{indent}#{safe_label}"

    children =
      map.graph
      |> Yog.successor_ids(node_id)
      |> Enum.filter(fn child_id ->
        meta = Map.get(map.edge_meta, {node_id, child_id}, %{})
        meta[:edge_type] == :branch and not MapSet.member?(visited, child_id)
      end)
      |> Enum.sort()

    visited = MapSet.union(visited, MapSet.new(children))
    children_lines = Enum.map(children, &render_mindmap_node(map, &1, depth + 1, visited))

    Enum.join([line | children_lines], "\n")
  end

  defp sanitize_mindmap_label(label) do
    label
    |> to_string()
    |> String.replace("\n", " ")
  end

  @doc """
  Returns a theme for `Choreo.MindMap` Mermaid diagrams.
  """
  @spec theme(atom(), keyword()) :: Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_mind_map_theme()
  defp resolve_theme(:dark), do: dark_mind_map_theme()
  defp resolve_theme(:warm), do: warm_mind_map_theme()
  defp resolve_theme(:forest), do: forest_mind_map_theme()
  defp resolve_theme(:ocean), do: ocean_mind_map_theme()
  defp resolve_theme(_), do: default_mind_map_theme()

  defp warm_mind_map_theme do
    %Theme{
      name: :mind_map_warm,
      colors: %{root: "#ec4899", topic: "#f97316", subtopic: "#fbbf24", note: "#fdba74"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#78716c",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#fef2f2"
    }
  end

  defp forest_mind_map_theme do
    %Theme{
      name: :mind_map_forest,
      colors: %{root: "#15803d", topic: "#166534", subtopic: "#65a30d", note: "#86efac"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#4b5563",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0fdf4"
    }
  end

  defp ocean_mind_map_theme do
    %Theme{
      name: :mind_map_ocean,
      colors: %{root: "#1d4ed8", topic: "#0284c7", subtopic: "#0ea5e9", note: "#7dd3fc"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0f9ff"
    }
  end

  defp default_mind_map_theme do
    %Theme{
      name: :mind_map_default,
      colors: %{root: "#8b5cf6", topic: "#3b82f6", subtopic: "#06b6d4", note: "#f59e0b"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: nil
    }
  end

  defp dark_mind_map_theme do
    %Theme{
      name: :mind_map_dark,
      colors: %{root: "#7c3aed", topic: "#2563eb", subtopic: "#0891b2", note: "#d97706"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#e2e8f0",
      edge_color: "#94a3b8",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#0f172a"
    }
  end

  defp mm_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_shape_fn(_id, data) do
    case Map.get(data, :node_type, :subtopic) do
      :root -> :circle
      :topic -> :rounded_rect
      :subtopic -> :subroutine
      :note -> :rounded_rect
      _ -> :subroutine
    end
  end

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :subtopic) do
          :root ->
            [
              {:fill, mm_color(theme, :root)},
              {:stroke, Choreo.Internal.darken(mm_color(theme, :root))},
              {:stroke_width, "3px"}
            ]

          :topic ->
            [
              {:fill, mm_color(theme, :topic)},
              {:stroke, Choreo.Internal.darken(mm_color(theme, :topic))}
            ]

          :subtopic ->
            [
              {:fill, mm_color(theme, :subtopic)},
              {:stroke, Choreo.Internal.darken(mm_color(theme, :subtopic))}
            ]

          :note ->
            [
              {:fill, mm_color(theme, :note)},
              {:stroke, Choreo.Internal.darken(mm_color(theme, :note))}
            ]

          _ ->
            [
              {:fill, mm_color(theme, :subtopic)},
              {:stroke, Choreo.Internal.darken(mm_color(theme, :subtopic))}
            ]
        end

      base =
        if color = data[:fillcolor],
          do: [{:fill, color} | Keyword.delete(base, :fill)],
          else: base

      base =
        if penwidth = data[:penwidth],
          do: [{:stroke_width, "#{penwidth}px"} | base],
          else: base

      if MapSet.member?(hl_nodes, id) do
        Keyword.drop(base, [:fill])
      else
        base
      end
    end
  end

  defp node_label(_id, data) do
    data[:label] || ""
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(map, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(map.edge_meta, edge_id, %{})

      base =
        case meta[:edge_type] do
          :associates ->
            [{:stroke, "#94a3b8"}, {:stroke_width, "1px"}, {:stroke_dasharray, "5 5"}]

          :virtual ->
            [{:stroke, "#cbd5e1"}, {:stroke_width, "1px"}, {:stroke_dasharray, "5 5"}]

          _ ->
            [{:stroke, "#64748b"}, {:stroke_width, "1px"}]
        end

      is_highlighted =
        MapSet.member?(hl_edges, edge_id) or
          MapSet.member?(hl_edges, {from, to})

      if is_highlighted do
        Keyword.drop(base, [:stroke, :stroke_width])
      else
        base
      end
    end
  end

  defp edge_label(map, edge_id) do
    meta = Map.get(map.edge_meta, edge_id, %{})
    meta[:label] || ""
  end
end
