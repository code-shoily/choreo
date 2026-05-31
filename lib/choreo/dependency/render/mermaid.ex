defmodule Choreo.Dependency.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.Dependency` graphs.

  Produces dependency-oriented visualisation:

    * **Applications** — subroutine shapes
    * **Libraries** — cylinder shapes
    * **Modules** — rounded rectangles
    * **Interfaces** — rhombus shapes
    * **Tests** — rounded rectangles

  Edge styles:
    * **uses** — solid grey
    * **imports** — dashed
    * **calls** — dotted (styled as dashed in Mermaid with small dashes)
    * **inherits** — solid bold
    * **dev** — dashed grey

  Layout is top-to-bottom by default so dependencies point downward.
  """

  alias Choreo.Dependency
  alias Choreo.Theme

  @doc """
  Renders a dependency graph to a Mermaid flowchart string.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:td` (default), `:lr`, `:bt`, `:rl`
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of edge IDs/tuples to highlight

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api, label: "API")
      ...>   |> Choreo.Dependency.add_module(:auth, label: "Auth")
      ...>   |> Choreo.Dependency.depends_on(:api, :auth)
      iex> mermaid = Choreo.Dependency.Render.Mermaid.to_mermaid(deps)
      iex> String.contains?(mermaid, "graph TD")
      true
      iex> String.contains?(mermaid, "API")
      true
      iex> String.contains?(mermaid, "Auth")
      true
  """
  @spec to_mermaid(Choreo.Dependency.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.Dependency{} = deps, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :td)
    subgraphs = Choreo.Internal.build_mermaid_subgraphs(deps)
    cycle_edges = cycle_edge_set(deps)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    base_opts =
      Yog.Multi.Mermaid.default_options()
      |> Map.put(:direction, direction)
      |> Map.put(:node_shape, &node_shape_fn/2)
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(deps, edge_id) end)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(deps, cycle_edges, theme, hl_edges))
      |> Map.put(:default_font_color, theme.node_fontcolor)
      |> Map.put(:default_link_stroke, theme.edge_color)
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Multi.Mermaid.to_mermaid(deps.graph, base_opts)
    |> String.replace("stroke_dasharray", "stroke-dasharray")
  end

  # ============================================================================
  # Cycle highlighting
  # ============================================================================

  defp cycle_edge_set(deps) do
    cycles = Choreo.Dependency.Analysis.cyclic_dependencies(deps)

    cycles
    |> Enum.flat_map(fn path ->
      path
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [from, to] -> {from, to} end)
    end)
    |> MapSet.new()
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_dependency_theme()
  defp resolve_theme(:dark), do: dark_dependency_theme()
  defp resolve_theme(:warm), do: warm_dependency_theme()
  defp resolve_theme(:forest), do: forest_dependency_theme()
  defp resolve_theme(:ocean), do: ocean_dependency_theme()
  defp resolve_theme(_), do: default_dependency_theme()

  defp warm_dependency_theme do
    %Theme{
      name: :dependency_warm,
      colors: %{
        application: "#ea580c",
        library: "#fbbf24",
        module: "#f43f5e",
        interface: "#db2777",
        test: "#78716c"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#78716c",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: "#fef2f2",
      cluster_fillcolor: "#fee2e2",
      cluster_style: :rounded,
      cluster_color: "#fca5a5"
    }
  end

  defp forest_dependency_theme do
    %Theme{
      name: :dependency_forest,
      colors: %{
        application: "#047857",
        library: "#65a30d",
        module: "#15803d",
        interface: "#0f766e",
        test: "#4b5563"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#4b5563",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0fdf4",
      cluster_fillcolor: "#dcfce7",
      cluster_style: :rounded,
      cluster_color: "#86efac"
    }
  end

  defp ocean_dependency_theme do
    %Theme{
      name: :dependency_ocean,
      colors: %{
        application: "#0e7490",
        library: "#0891b2",
        module: "#1d4ed8",
        interface: "#008080",
        test: "#64748b"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0f9ff",
      cluster_fillcolor: "#e0f2fe",
      cluster_style: :rounded,
      cluster_color: "#7dd3fc"
    }
  end

  defp default_dependency_theme do
    %Theme{
      name: :dependency_default,
      colors: %{
        application: "#3b82f6",
        library: "#f59e0b",
        module: "#10b981",
        interface: "#8b5cf6",
        test: "#64748b"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: nil,
      cluster_fillcolor: "#f8fafc",
      cluster_style: :rounded,
      cluster_color: "#cbd5e1"
    }
  end

  defp dark_dependency_theme do
    %Theme{
      name: :dependency_dark,
      colors: %{
        application: "#2563eb",
        library: "#d97706",
        module: "#059669",
        interface: "#7c3aed",
        test: "#475569"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#e2e8f0",
      edge_color: "#94a3b8",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: "#0f172a",
      cluster_fillcolor: "#1e293b",
      cluster_style: :rounded,
      cluster_color: "#475569"
    }
  end

  defp dep_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_shape_fn(_id, data) do
    case Map.get(data, :node_type, :module) do
      :application -> :subroutine
      :library -> :cylinder
      :module -> :rounded_rect
      :interface -> :rhombus
      :test -> :rounded_rect
      _ -> :rounded_rect
    end
  end

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :module) do
          :application ->
            [
              {:fill, dep_color(theme, :application)},
              {:stroke, Choreo.Internal.darken(dep_color(theme, :application))}
            ]

          :library ->
            [
              {:fill, dep_color(theme, :library)},
              {:stroke, Choreo.Internal.darken(dep_color(theme, :library))}
            ]

          :module ->
            [
              {:fill, dep_color(theme, :module)},
              {:stroke, Choreo.Internal.darken(dep_color(theme, :module))}
            ]

          :interface ->
            [
              {:fill, dep_color(theme, :interface)},
              {:stroke, Choreo.Internal.darken(dep_color(theme, :interface))}
            ]

          :test ->
            [
              {:fill, dep_color(theme, :test)},
              {:stroke, Choreo.Internal.darken(dep_color(theme, :test))}
            ]

          _ ->
            [
              {:fill, dep_color(theme, :module)},
              {:stroke, Choreo.Internal.darken(dep_color(theme, :module))}
            ]
        end

      base =
        if shape = data[:shape] do
          # Map overrides
          shape_attr =
            case shape do
              :box3d -> :subroutine
              :cylinder -> :cylinder
              :box -> :rounded_rect
              :diamond -> :rhombus
              :note -> :rounded_rect
              _ -> :rounded_rect
            end

          # Note: Yog.Multi.Mermaid uses node_shape_fn for basic shape, but custom overrides can be defined
          base
        else
          base
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

  defp edge_attributes_fn(deps, cycle_edges, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(deps.edge_meta, edge_id, %{})

      if meta[:edge_type] == :virtual do
        [{:stroke, "#cbd5e1"}, {:stroke_width, "1px"}, {:stroke_dasharray, "5 5"}]
      else
        base = dep_type_attrs(meta[:type] || :uses, theme)

        # Highlight cycle edges in red and thick stroke
        base =
          if MapSet.member?(cycle_edges, {from, to}) do
            [
              {:stroke, "#ef4444"},
              {:stroke_width, "3px"} | Keyword.drop(base, [:stroke, :stroke_width])
            ]
          else
            base
          end

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

  defp dep_type_attrs(:imports, theme),
    do: [{:stroke, theme.edge_color}, {:stroke_dasharray, "5 5"}, {:stroke_width, "2px"}]

  defp dep_type_attrs(:calls, theme),
    do: [{:stroke, theme.edge_color}, {:stroke_dasharray, "2 3"}, {:stroke_width, "2px"}]

  defp dep_type_attrs(:inherits, theme), do: [{:stroke, theme.edge_color}, {:stroke_width, "3px"}]

  defp dep_type_attrs(:dev, _theme),
    do: [{:stroke, "#9ca3af"}, {:stroke_dasharray, "5 5"}, {:stroke_width, "1.5px"}]

  defp dep_type_attrs(_, theme), do: [{:stroke, theme.edge_color}, {:stroke_width, "2px"}]

  defp edge_label(deps, edge_id) do
    meta = Map.get(deps.edge_meta, edge_id, %{})
    meta[:label] || ""
  end
end
