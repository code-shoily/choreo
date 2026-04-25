defmodule Choreo.ThreatModel.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.ThreatModel`.

  Produces security-oriented visualisation:

    * **External entities** — rectangles with double border
    * **Processes** — circles
    * **Data stores** — cylinders
    * **Trust boundaries** — thick red dashed rectangles
    * **Cross-boundary flows** — highlighted edges
    * **Unencrypted flows** — red dashed edges
  """

  alias Choreo.Theme
  alias Choreo.ThreatModel

  @doc """
  Renders a threat model to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct
  """
  @spec to_dot(Choreo.ThreatModel.t(), keyword()) :: String.t()
  def to_dot(%Choreo.ThreatModel{} = model, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    subgraphs = build_boundary_subgraphs(model, theme)

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
      |> Map.put(:edge_label, &edge_label/1)
      |> Map.put(:node_attributes, node_attributes_fn(theme))
      |> Map.put(:edge_attributes, edge_attributes_fn(model))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Render.DOT.to_dot(model.graph, base_opts)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_threat_theme()
  defp resolve_theme(:dark), do: dark_threat_theme()
  defp resolve_theme(_), do: default_threat_theme()

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

  defp theme_graph_overrides(%Theme{graph_bgcolor: nil}), do: %{}
  defp theme_graph_overrides(%Theme{graph_bgcolor: bg}), do: %{bgcolor: bg}

  # ============================================================================
  # Boundary / subgraph builders
  # ============================================================================

  defp build_boundary_subgraphs(model, theme) do
    boundaries = model.boundaries

    if map_size(boundaries) == 0 do
      []
    else
      nodes_by_boundary =
        model.graph.nodes
        |> Enum.group_by(fn {_id, data} -> data[:boundary] end)
        |> Map.delete(nil)

      Enum.map(Map.keys(boundaries), fn name ->
        boundary = Map.get(boundaries, name, %{})

        %{
          name: name,
          label: boundary[:label] || name,
          node_ids: nodes_by_boundary |> Map.get(name, []) |> Enum.map(fn {id, _data} -> id end),
          style: boundary[:style] || theme.cluster_style,
          fillcolor: boundary[:fillcolor] || theme.cluster_fillcolor,
          color: boundary[:color] || theme.cluster_color,
          penwidth: 2.0,
          subgraphs: nil
        }
      end)
    end
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme) do
    fn _id, data ->
      case Map.get(data, :element_type, :process) do
        :external_entity ->
          [
            {:shape, :box},
            {:fillcolor, threat_color(theme, :external_entity)},
            {:penwidth, 2.0}
          ]

        :process ->
          [
            {:shape, :circle},
            {:fillcolor, threat_color(theme, :process)}
          ]

        :data_store ->
          [
            {:shape, :cylinder},
            {:fillcolor, threat_color(theme, :data_store)}
          ]

        _ ->
          [
            {:shape, :box},
            {:fillcolor, threat_color(theme, :process)}
          ]
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
    fn from, to, _weight ->
      meta = Map.get(model.edge_meta, {from, to}, %{})
      crosses = ThreatModel.crosses_boundary?(model, from, to)
      encrypted = meta[:encrypted] == true

      base =
        cond do
          not encrypted and crosses ->
            [{:color, "#ef4444"}, {:penwidth, 2.0}, {:style, "dashed"}]

          crosses ->
            [{:color, "#f59e0b"}, {:penwidth, 1.5}]

          true ->
            [{:color, "#64748b"}, {:penwidth, 1.0}]
        end

      base = if proto = meta[:protocol], do: [{:label, to_string(proto)} | base], else: base

      base
    end
  end

  defp edge_label(weight) when is_binary(weight) and weight != "", do: weight
  defp edge_label(_), do: ""
end
