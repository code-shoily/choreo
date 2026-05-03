defmodule Choreo.ThreatModel.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.ThreatModel`.

  Produces security-oriented visualisation:

    * **External entities** — rectangles with thick border
    * **Processes** — circles
    * **Data stores** — cylinders
    * **Trust boundaries** — thick red dashed rectangles
    * **Cross-boundary flows** — highlighted edges
    * **Unencrypted flows** — red dashed edges

  ## Further reading

    * [DOT Language Reference](https://graphviz.org/doc/info/lang.html)
    * [Microsoft Threat Modeling Tool DFD Shapes](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-getting-started)
  """

  alias Choreo.Theme
  alias Choreo.ThreatModel

  @doc """
  Renders a threat model to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_external_entity(:user, label: "User")
      ...>   |> Choreo.ThreatModel.add_process(:api, label: "API")
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api, label: "HTTPS")
      iex> dot = Choreo.ThreatModel.Render.DOT.to_dot(model)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "User")
      true
      iex> String.contains?(dot, "API")
      true
  """
  @spec to_dot(Choreo.ThreatModel.t(), keyword()) :: String.t()
  def to_dot(%Choreo.ThreatModel{} = model, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    subgraphs = Choreo.Internal.build_cluster_subgraphs(model, theme)

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
      |> Map.put(:node_attributes, node_attributes_fn(theme))
      |> Map.put(:edge_attributes, edge_attributes_fn(model))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Multi.DOT.to_dot(model.graph, base_opts)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_threat_theme()
  defp resolve_theme(:dark), do: dark_threat_theme()
  defp resolve_theme(:warm), do: warm_threat_theme()
  defp resolve_theme(:forest), do: forest_threat_theme()
  defp resolve_theme(:ocean), do: ocean_threat_theme()
  defp resolve_theme(_), do: default_threat_theme()

  defp warm_threat_theme do
    %Theme{
      name: :threat_warm,
      colors: %{
        external_entity: "#f43f5e",
        process: "#f97316",
        data_store: "#ea580c"
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
      cluster_style: :dashed,
      cluster_color: "#ef4444"
    }
  end

  defp forest_threat_theme do
    %Theme{
      name: :threat_forest,
      colors: %{
        external_entity: "#15803d",
        process: "#14b8a6",
        data_store: "#047857"
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
      cluster_style: :dashed,
      cluster_color: "#ef4444"
    }
  end

  defp ocean_threat_theme do
    %Theme{
      name: :threat_ocean,
      colors: %{
        external_entity: "#1d4ed8",
        process: "#0ea5e9",
        data_store: "#0369a1"
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
      cluster_style: :dashed,
      cluster_color: "#ef4444"
    }
  end

  defp default_threat_theme do
    %Theme{
      name: :threat_default,
      colors: %{
        external_entity: "#64748b",
        process: "#3b82f6",
        data_store: "#f59e0b"
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
      cluster_style: :dashed,
      cluster_color: "#ef4444"
    }
  end

  defp dark_threat_theme do
    %Theme{
      name: :threat_dark,
      colors: %{
        external_entity: "#475569",
        process: "#2563eb",
        data_store: "#d97706"
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
      cluster_style: :dashed,
      cluster_color: "#ef4444"
    }
  end

  defp threat_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  defp theme_graph_overrides(%Theme{} = theme) do
    base = if theme.graph_rankdir != nil, do: %{rankdir: theme.graph_rankdir}, else: %{}
    if theme.graph_bgcolor != nil, do: Map.put(base, :bgcolor, theme.graph_bgcolor), else: base
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme) do
    fn _id, data ->
      base =
        case Map.get(data, :element_type, :process) do
          :external_entity ->
            [
              {:shape, :box},
              {:fillcolor, threat_color(theme, :external_entity)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"},
              {:penwidth, 2.0}
            ]

          :process ->
            [
              {:shape, :circle},
              {:fillcolor, threat_color(theme, :process)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :data_store ->
            [
              {:shape, :cylinder},
              {:fillcolor, threat_color(theme, :data_store)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          _ ->
            [
              {:shape, :box},
              {:fillcolor, threat_color(theme, :process)},
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

      if desc = data[:description] do
        [{:tooltip, desc} | base]
      else
        base
      end
    end
  end

  defp node_label(_id, data) do
    label = data[:label] || ""

    label =
      if priv = data[:privilege] do
        "#{label}\n(#{priv})"
      else
        label
      end

    label =
      if sens = data[:sensitivity] do
        "#{label}\n[#{sens}]"
      else
        label
      end

    label
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(model) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(model.edge_meta, edge_id, %{})

      if meta[:edge_type] == :virtual do
        [{:color, "#cbd5e1"}, {:style, "dashed"}, {:penwidth, 0.8}]
      else
        crosses = ThreatModel.crosses_boundary?(model, from, to)
        encrypted = meta[:encrypted] == true

        base =
          cond do
            not encrypted and crosses ->
              [{:color, "#ef4444"}, {:fontcolor, "#ef4444"}, {:penwidth, 2.0}, {:style, "dashed"}]

            crosses ->
              [{:color, "#f59e0b"}, {:fontcolor, "#f59e0b"}, {:penwidth, 1.5}]

            true ->
              [{:color, "#64748b"}, {:fontcolor, "#64748b"}, {:penwidth, 1.0}]
          end

        base = if proto = meta[:protocol], do: [{:label, to_string(proto)} | base], else: base

        base
      end
    end
  end

  defp edge_label(weight) when is_binary(weight) and weight != "", do: weight
  defp edge_label(_), do: ""
end
