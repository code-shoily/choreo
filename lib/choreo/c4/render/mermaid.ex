defmodule Choreo.C4.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.C4` architecture diagrams.

  Produces C4-model-oriented flowchart visualisation:

    * **Person** — circle shape `((Label))`
    * **Software System** — rounded rectangle `[Label]`
    * **Container** — stadium shape `([Label])`
    * **Component** — subroutine shape `[[Label]]`

  Relationships are rendered as directed links with labels.
  Clusters group containers by their parent software system and
  components by their parent container.

  ## Further reading

    * [C4 Model notation](https://c4model.com/)
    * [Mermaid flowchart syntax](https://mermaid.js.org/syntax/flowchart.html)
  """

  alias Choreo.C4
  alias Choreo.Theme

  @doc """
  Renders a C4 model to a Mermaid flowchart string.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:lr` (default), `:td`, `:rl`, `:bt`
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of edge IDs or `{from, to}` tuples to highlight

  ## Examples

      iex> c4 = Choreo.C4.new()
      iex> c4 = c4
      ...>   |> Choreo.C4.add_person(:user, label: "User")
      ...>   |> Choreo.C4.add_software_system(:app, label: "App")
      ...>   |> Choreo.C4.add_relationship(:user, :app, label: "Uses")
      iex> mermaid = Choreo.C4.Render.Mermaid.to_mermaid(c4)
      iex> String.contains?(mermaid, "graph LR")
      true
      iex> String.contains?(mermaid, "User")
      true
      iex> String.contains?(mermaid, "App")
      true
  """
  @spec to_mermaid(C4.t(), keyword()) :: String.t()
  def to_mermaid(%C4{} = c4, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :lr)
    subgraphs = Choreo.Internal.build_mermaid_subgraphs(c4)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    base_opts =
      Yog.Multi.Mermaid.default_options()
      |> Map.put(:direction, direction)
      |> Map.put(:node_shape, &node_shape_fn/2)
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(c4, edge_id) end)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(c4, theme, hl_edges))
      |> Map.put(:default_font_color, theme.node_fontcolor)
      |> Map.put(:default_link_stroke, theme.edge_color)
      |> Map.merge(Map.new(opts))

    base_opts =
      if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Multi.Mermaid.to_mermaid(c4.graph, base_opts)
    |> String.replace("stroke_dasharray", "stroke-dasharray")
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_c4_theme()
  defp resolve_theme(:dark), do: dark_c4_theme()
  defp resolve_theme(:warm), do: warm_c4_theme()
  defp resolve_theme(:forest), do: forest_c4_theme()
  defp resolve_theme(:ocean), do: ocean_c4_theme()
  defp resolve_theme(_), do: default_c4_theme()

  defp warm_c4_theme do
    %Theme{
      name: :c4_warm,
      colors: %{
        person: "#f43f5e",
        software_system: "#f97316",
        container: "#fbbf24",
        component: "#ea580c"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#78716c",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#fef2f2",
      cluster_fillcolor: "#fee2e2",
      cluster_style: :rounded,
      cluster_color: "#fca5a5"
    }
  end

  defp forest_c4_theme do
    %Theme{
      name: :c4_forest,
      colors: %{
        person: "#15803d",
        software_system: "#047857",
        container: "#65a30d",
        component: "#14b8a6"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#4b5563",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0fdf4",
      cluster_fillcolor: "#dcfce7",
      cluster_style: :rounded,
      cluster_color: "#86efac"
    }
  end

  defp ocean_c4_theme do
    %Theme{
      name: :c4_ocean,
      colors: %{
        person: "#1d4ed8",
        software_system: "#0369a1",
        container: "#0891b2",
        component: "#0ea5e9"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0f9ff",
      cluster_fillcolor: "#e0f2fe",
      cluster_style: :rounded,
      cluster_color: "#7dd3fc"
    }
  end

  defp default_c4_theme do
    %Theme{
      name: :c4_default,
      colors: %{
        person: "#84cc16",
        software_system: "#3b82f6",
        container: "#10b981",
        component: "#8b5cf6"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: nil,
      cluster_fillcolor: "#f8fafc",
      cluster_style: :rounded,
      cluster_color: "#cbd5e1"
    }
  end

  defp dark_c4_theme do
    %Theme{
      name: :c4_dark,
      colors: %{
        person: "#65a30d",
        software_system: "#2563eb",
        container: "#059669",
        component: "#7c3aed"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#e2e8f0",
      edge_color: "#94a3b8",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#0f172a",
      cluster_fillcolor: "#1e293b",
      cluster_style: :rounded,
      cluster_color: "#475569"
    }
  end

  defp c4_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_shape_fn(_id, data) do
    case Map.get(data, :node_type, :software_system) do
      :person -> :circle
      :software_system -> :rounded_rect
      :container -> :stadium
      :component -> :subroutine
      _ -> :rounded_rect
    end
  end

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :software_system) do
          :person ->
            [
              {:fill, c4_color(theme, :person)},
              {:stroke, Choreo.Internal.darken(c4_color(theme, :person))},
              {:stroke_width, "3px"}
            ]

          :software_system ->
            [
              {:fill, c4_color(theme, :software_system)},
              {:stroke, Choreo.Internal.darken(c4_color(theme, :software_system))},
              {:stroke_width, "2px"}
            ]

          :container ->
            [
              {:fill, c4_color(theme, :container)},
              {:stroke, Choreo.Internal.darken(c4_color(theme, :container))},
              {:stroke_width, "2px"}
            ]

          :component ->
            [
              {:fill, c4_color(theme, :component)},
              {:stroke, Choreo.Internal.darken(c4_color(theme, :component))},
              {:stroke_width, "2px"},
              {:stroke_dasharray, "5 5"}
            ]

          _ ->
            [
              {:fill, c4_color(theme, :software_system)},
              {:stroke, Choreo.Internal.darken(c4_color(theme, :software_system))}
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
    label = data[:label] || ""
    tech = data[:technology]

    if tech && tech != "" do
      "#{label}\n[#{tech}]"
    else
      label
    end
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(c4, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(c4.edge_meta, edge_id, %{})

      if meta[:edge_type] == :virtual do
        [{:stroke, "#cbd5e1"}, {:stroke_width, "1px"}, {:stroke_dasharray, "5 5"}]
      else
        base = [{:stroke, theme.edge_color}, {:stroke_width, "2px"}]

        # Handle highlighting: Omit stroke/stroke_width if edge is highlighted
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
  end

  defp edge_label(c4, edge_id) do
    meta = Map.get(c4.edge_meta, edge_id, %{})
    label = meta[:label] || ""
    tech = meta[:technology]

    cond do
      tech && tech != "" ->
        "\"#{label} [#{tech}]\""

      label != "" ->
        "\"#{label}\""

      true ->
        ""
    end
  end
end
