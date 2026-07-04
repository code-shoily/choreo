defmodule Choreo.C4.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.C4` architecture diagrams.

  Produces C4-model-oriented visualisation:

    * **Person** — ellipse with thick border
    * **Software System** — rectangle with solid border
    * **Container** — rounded rectangle with solid border
    * **Component** — rectangle with dashed border

  Relationships are rendered as directed edges with labels.
  Clusters group containers by their parent software system and
  components by their parent container.

  ## Further reading

    * [C4 Model notation](https://c4model.com/)
    * [DOT Language Reference](https://graphviz.org/doc/info/lang.html)
  """

  alias Choreo.C4
  alias Choreo.Theme

  @doc """
  Renders a C4 model to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct

  ## Examples

      iex> c4 = Choreo.C4.new()
      iex> c4 = c4
      ...>   |> Choreo.C4.add_person(:user, label: "User")
      ...>   |> Choreo.C4.add_software_system(:app, label: "App")
      ...>   |> Choreo.C4.add_relationship(:user, :app, label: "Uses")
      iex> dot = Choreo.C4.Render.DOT.to_dot(c4)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "User")
      true
      iex> String.contains?(dot, "App")
      true
  """
  @spec to_dot(C4.t(), keyword()) :: String.t()
  def to_dot(%C4{} = c4, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    states_list = C4.nodes(c4)
    id_map = Enum.into(states_list, %{}, fn id -> {id, dot_id(id)} end)
    safe_graph = Choreo.Internal.make_multi_graph_safe(c4.graph, id_map)
    safe_c4 = %{c4 | graph: safe_graph}

    subgraphs = Choreo.Internal.build_cluster_subgraphs(safe_c4, theme)

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
      |> Map.put(:rankdir, :lr)
      |> Map.put(:splines, :spline)
      |> Map.put(:nodesep, 0.6)
      |> Map.put(:ranksep, 1.2)
      |> Map.put(:node_shape, :box)
      |> Map.put(:node_style, :filled)
      |> Map.put(:node_color, "white")
      |> Map.put(:node_fontname, theme.node_fontname)
      |> Map.put(:node_fontsize, theme.node_fontsize)
      |> Map.put(:node_fontcolor, theme.node_fontcolor)
      |> Map.put(:edge_color, theme.edge_color)
      |> Map.put(:edge_fontname, theme.edge_fontname)
      |> Map.put(:edge_fontsize, theme.edge_fontsize)
      |> Map.put(:edge_penwidth, theme.edge_penwidth)
      |> Map.put(:arrowhead, :normal)
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn _edge_id, label -> edge_label(label) end)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(safe_c4, hl_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

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
  defp resolve_theme(:default), do: default_c4_theme()
  defp resolve_theme(:dark), do: dark_c4_theme()
  defp resolve_theme(:minimal), do: minimal_c4_theme()
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

  defp minimal_c4_theme do
    %Theme{default_c4_theme() | name: :c4_minimal}
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

  defp theme_graph_overrides(%Theme{} = theme) do
    base = if theme.graph_rankdir != nil, do: %{rankdir: theme.graph_rankdir}, else: %{}
    if theme.graph_bgcolor != nil, do: Map.put(base, :bgcolor, theme.graph_bgcolor), else: base
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :software_system) do
          :person ->
            [
              {:shape, :ellipse},
              {:fillcolor, c4_color(theme, :person)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"},
              {:penwidth, 2.0}
            ]

          :software_system ->
            [
              {:shape, :box},
              {:fillcolor, c4_color(theme, :software_system)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"},
              {:penwidth, 1.5}
            ]

          :container ->
            [
              {:shape, :box},
              {:fillcolor, c4_color(theme, :container)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "rounded,filled"},
              {:penwidth, 1.5}
            ]

          :component ->
            [
              {:shape, :box},
              {:fillcolor, c4_color(theme, :component)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled,dashed"},
              {:penwidth, 1.5}
            ]

          _ ->
            [
              {:shape, :box},
              {:fillcolor, c4_color(theme, :software_system)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]
        end

      base =
        if shape = data[:shape], do: [{:shape, shape} | Keyword.delete(base, :shape)], else: base

      base =
        if color = data[:fillcolor],
          do: [{:fillcolor, color} | Keyword.delete(base, :fillcolor)],
          else: base

      base =
        if fontcolor = data[:fontcolor],
          do: [{:fontcolor, fontcolor} | Keyword.delete(base, :fontcolor)],
          else: base

      base =
        if style = data[:style], do: [{:style, style} | Keyword.delete(base, :style)], else: base

      base =
        if penwidth = data[:penwidth],
          do: [{:penwidth, penwidth} | Keyword.delete(base, :penwidth)],
          else: base

      base =
        if image = data[:image],
          do: [{:image, image} | Keyword.delete(base, :image)],
          else: base

      base =
        if desc = data[:description] do
          [{:tooltip, desc} | base]
        else
          base
        end

      # Final highlighting override: Omit fillcolor if node is highlighted
      if MapSet.member?(hl_nodes, id) do
        Keyword.drop(base, [:fillcolor])
      else
        base
      end
    end
  end

  defp node_label(_id, data) do
    label = data[:label] || ""
    tech = data[:technology]

    if tech && tech != "" do
      "#{label}\\n[#{tech}]"
    else
      label
    end
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(c4, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(c4.edge_meta, edge_id, %{})

      if meta[:edge_type] == :virtual do
        [{:color, "#cbd5e1"}, {:style, "dashed"}, {:penwidth, 0.8}]
      else
        base = [{:color, "#64748b"}, {:penwidth, 1.0}]

        base =
          if label = meta[:label] do
            if label != "" do
              [{:label, to_string(label)} | base]
            else
              base
            end
          else
            base
          end

        base =
          if tech = meta[:technology] do
            if tech != "" do
              [{:label, "#{meta[:label] || ""} [#{tech}]"} | base]
            else
              base
            end
          else
            base
          end

        # Handle highlighting: Omit color/penwidth if edge is highlighted
        if MapSet.member?(hl_edges, edge_id) or MapSet.member?(hl_edges, {from, to}) do
          Keyword.drop(base, [:color, :penwidth])
        else
          base
        end
      end
    end
  end

  defp edge_label(_), do: ""

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
