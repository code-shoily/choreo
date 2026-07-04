defmodule Choreo.Planner.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.Planner` dependency networks.

  Tasks are rendered as rounded rectangles color-coded by status,
  milestones as diamonds, users as circles, and labels as stadiums.
  """

  alias Choreo.Planner
  alias Choreo.Theme

  @status_colors %{
    done: "#4ade80",
    in_progress: "#60a5fa",
    backlog: "#e5e7eb",
    todo: "#fcd34d",
    in_review: "#c084fc",
    cancelled: "#f87171"
  }

  @doc """
  Renders a planner project to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:tb` (default), `:lr`, `:rl`, `:bt`
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of edge IDs or `{from, to}` tuples to highlight
  """
  @spec to_dot(Planner.t(), keyword()) :: String.t()
  def to_dot(%Planner{} = planner, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    direction =
      case Keyword.get(opts, :direction, :tb) do
        :td -> :tb
        other -> other
      end

    states_list = Map.keys(planner.graph.nodes)
    id_map = Enum.into(states_list, %{}, fn id -> {id, dot_id(id)} end)
    safe_graph = Choreo.Internal.make_multi_graph_safe(planner.graph, id_map)
    safe_planner = %{planner | graph: safe_graph}

    hl_nodes =
      Keyword.get(opts, :highlighted_nodes, [])
      |> Kernel.||([])
      |> Enum.map(&dot_id/1)
      |> MapSet.new()

    hl_edges =
      Keyword.get(opts, :highlighted_edges, [])
      |> Kernel.||([])
      |> Enum.map(fn
        {from, to} -> {dot_id(from), dot_id(to)}
        other -> other
      end)
      |> MapSet.new()

    base_opts =
      Yog.Render.DOT.default_options()
      |> Map.put(:rankdir, direction)
      |> Map.put(:splines, :spline)
      |> Map.put(:nodesep, 0.6)
      |> Map.put(:ranksep, 1.2)
      |> Map.put(:node_shape, :box)
      |> Map.put(:node_style, :filled)
      |> Map.put(:node_fontname, theme.node_fontname)
      |> Map.put(:node_fontsize, theme.node_fontsize)
      |> Map.put(:node_fontcolor, theme.node_fontcolor)
      |> Map.put(:edge_color, theme.edge_color)
      |> Map.put(:edge_fontname, theme.edge_fontname)
      |> Map.put(:edge_fontsize, theme.edge_fontsize)
      |> Map.put(:edge_penwidth, theme.edge_penwidth)
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn _eid, _w -> "" end)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(safe_planner, theme, hl_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(Keyword.drop(opts, [:theme, :direction])))

    Yog.Multi.DOT.to_dot(safe_graph, base_opts)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_planner_theme()
  defp resolve_theme(:dark), do: dark_planner_theme()
  defp resolve_theme(:minimal), do: minimal_planner_theme()
  defp resolve_theme(:warm), do: warm_planner_theme()
  defp resolve_theme(:forest), do: forest_planner_theme()
  defp resolve_theme(:ocean), do: ocean_planner_theme()
  defp resolve_theme(_), do: default_planner_theme()

  defp warm_planner_theme do
    %Theme{
      name: :planner_warm,
      colors: %{task: "#f97316", milestone: "#f43f5e", user: "#db2777", label: "#ea580c"},
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

  defp forest_planner_theme do
    %Theme{
      name: :planner_forest,
      colors: %{task: "#15803d", milestone: "#047857", user: "#166534", label: "#65a30d"},
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

  defp ocean_planner_theme do
    %Theme{
      name: :planner_ocean,
      colors: %{task: "#0ea5e9", milestone: "#0369a1", user: "#1d4ed8", label: "#0891b2"},
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

  defp minimal_planner_theme do
    %Theme{default_planner_theme() | name: :planner_minimal}
  end

  defp default_planner_theme do
    %Theme{
      name: :planner_default,
      colors: %{task: "#3b82f6", milestone: "#8b5cf6", user: "#10b981", label: "#f59e0b"},
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

  defp dark_planner_theme do
    %Theme{
      name: :planner_dark,
      colors: %{task: "#2563eb", milestone: "#7c3aed", user: "#059669", label: "#d97706"},
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

  defp planner_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  defp theme_graph_overrides(%Theme{} = theme), do: Choreo.Theme.graph_overrides(theme)

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_label(_id, data) do
    data[:title] || data[:label] || data[:name] || ""
  end

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      type = Map.get(data, :node_type, :task)

      base =
        case type do
          :task ->
            status = data[:status] || :backlog
            fill = Map.get(@status_colors, status, "#e5e7eb")

            [
              {:fillcolor, fill},
              {:color, Choreo.Internal.darken(fill)},
              {:shape, :box},
              {:style, "rounded,filled"}
            ]

          :milestone ->
            fill = planner_color(theme, :milestone)

            [
              {:fillcolor, fill},
              {:color, Choreo.Internal.darken(fill)},
              {:shape, :diamond},
              {:style, "filled"},
              {:penwidth, "2.0"}
            ]

          :user ->
            fill = planner_color(theme, :user)

            [
              {:fillcolor, fill},
              {:color, Choreo.Internal.darken(fill)},
              {:shape, :circle},
              {:style, "filled"}
            ]

          :label ->
            fill = planner_color(theme, :label)

            [
              {:fillcolor, fill},
              {:color, Choreo.Internal.darken(fill)},
              {:shape, :stadium},
              {:style, "filled"}
            ]

          _ ->
            fill = planner_color(theme, :task)

            [
              {:fillcolor, fill},
              {:color, Choreo.Internal.darken(fill)},
              {:shape, :box},
              {:style, "rounded,filled"}
            ]
        end

      base =
        if color = data[:fillcolor] do
          [{:fillcolor, color} | Keyword.delete(base, :fillcolor)]
        else
          base
        end

      base =
        if penwidth = data[:penwidth] do
          [{:penwidth, penwidth} | base]
        else
          base
        end

      if MapSet.member?(hl_nodes, id) do
        [{:color, "#ef4444"}, {:penwidth, "2.0"} | base]
      else
        base
      end
    end
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(planner, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(planner.edge_meta, edge_id, %{})

      base =
        case meta[:type] do
          :depends_on -> [{:color, theme.edge_color}, {:penwidth, theme.edge_penwidth}]
          :blocks -> [{:color, "#ef4444"}, {:penwidth, "1.5"}, {:style, "dashed"}]
          :contains -> [{:color, "#94a3b8"}, {:penwidth, "1.0"}, {:style, "dashed"}]
          :assigned_to -> [{:color, "#10b981"}, {:penwidth, "1.0"}, {:style, "dashed"}]
          :tagged_with -> [{:color, "#f59e0b"}, {:penwidth, "1.0"}, {:style, "dashed"}]
          :relates_to -> [{:color, "#cbd5e1"}, {:penwidth, "1.0"}, {:style, "dashed"}]
          _ -> [{:color, theme.edge_color}, {:penwidth, theme.edge_penwidth}]
        end

      is_highlighted =
        MapSet.member?(hl_edges, edge_id) or
          MapSet.member?(hl_edges, {from, to})

      # Highlight override
      if is_highlighted do
        [{:color, "#ef4444"}, {:penwidth, "2.0"} | Keyword.drop(base, [:color, :penwidth])]
      else
        base
      end
    end
  end

  defp dot_id(id) do
    str =
      cond do
        is_atom(id) -> Atom.to_string(id)
        is_binary(id) -> id
        true -> inspect(id)
      end

    if str =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/ do
      str
    else
      "\"" <> String.replace(str, "\"", "\\\"") <> "\""
    end
  end
end
