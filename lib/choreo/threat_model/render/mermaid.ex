defmodule Choreo.ThreatModel.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.ThreatModel` graphs.

  Produces security-oriented visualization:

    * **External entities** — thick-bordered rectangles
    * **Processes** — circles
    * **Data stores** — cylinders
    * **Trust boundaries** — subgraphs grouping security elements
    * **Cross-boundary flows** — styled with high-scrutiny colors (red/orange)
    * **Unencrypted flows crossing boundaries** — styled as red dashed links

  Layout is left-to-right (LR) by default so data flows horizontally.
  """

  alias Choreo.Theme
  alias Choreo.ThreatModel

  @doc """
  Renders a threat model to a Mermaid flowchart string.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:lr` (default), `:td`, `:rl`, `:bt`
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of edge IDs/tuples to highlight

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_external_entity(:user, label: "User")
      ...>   |> Choreo.ThreatModel.add_process(:api, label: "API")
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api, label: "HTTPS")
      iex> mermaid = Choreo.ThreatModel.Render.Mermaid.to_mermaid(model)
      iex> String.contains?(mermaid, "graph LR")
      true
      iex> String.contains?(mermaid, "User")
      true
      iex> String.contains?(mermaid, "API")
      true
  """
  @spec to_mermaid(Choreo.ThreatModel.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.ThreatModel{} = model, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :lr)
    subgraphs = Choreo.Internal.build_mermaid_subgraphs(model)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    base_opts =
      Yog.Multi.Mermaid.default_options()
      |> Map.put(:direction, direction)
      |> Map.put(:node_shape, &node_shape_fn/2)
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(model, edge_id) end)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(model, theme, hl_edges))
      |> Map.put(:default_font_color, theme.node_fontcolor)
      |> Map.put(:default_link_stroke, theme.edge_color)
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Multi.Mermaid.to_mermaid(model.graph, base_opts)
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
  defp resolve_theme(:default), do: default_threat_theme()
  defp resolve_theme(:dark), do: dark_threat_theme()
  defp resolve_theme(:minimal), do: minimal_threat_theme()
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

  defp minimal_threat_theme do
    %Theme{default_threat_theme() | name: :threat_minimal}
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

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_shape_fn(_id, data) do
    case Map.get(data, :element_type, :process) do
      :external_entity -> :rounded_rect
      :process -> :circle
      :data_store -> :cylinder
      _ -> :rounded_rect
    end
  end

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :element_type, :process) do
          :external_entity ->
            [
              {:fill, threat_color(theme, :external_entity)},
              {:stroke, Choreo.Internal.darken(threat_color(theme, :external_entity))},
              {:stroke_width, "3px"}
            ]

          :process ->
            [
              {:fill, threat_color(theme, :process)},
              {:stroke, Choreo.Internal.darken(threat_color(theme, :process))}
            ]

          :data_store ->
            [
              {:fill, threat_color(theme, :data_store)},
              {:stroke, Choreo.Internal.darken(threat_color(theme, :data_store))}
            ]

          _ ->
            [
              {:fill, threat_color(theme, :process)},
              {:stroke, Choreo.Internal.darken(threat_color(theme, :process))}
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

    label =
      if priv = data[:privilege] do
        "#{label} (#{priv})"
      else
        label
      end

    label =
      if sens = data[:sensitivity] do
        "#{label} [#{sens}]"
      else
        label
      end

    label
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(model, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(model.edge_meta, edge_id, %{})

      if meta[:edge_type] == :virtual do
        [{:stroke, "#cbd5e1"}, {:stroke_width, "1px"}, {:stroke_dasharray, "5 5"}]
      else
        crosses = ThreatModel.crosses_boundary?(model, from, to)
        encrypted = meta[:encrypted] == true

        base =
          cond do
            not encrypted and crosses ->
              [
                {:stroke, "#ef4444"},
                {:stroke_width, "3px"},
                {:stroke_dasharray, "5 5"}
              ]

            crosses ->
              [{:stroke, "#f59e0b"}, {:stroke_width, "2.5px"}]

            true ->
              [{:stroke, theme.edge_color}, {:stroke_width, "2px"}]
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

  defp edge_label(model, edge_id) do
    meta = Map.get(model.edge_meta, edge_id, %{})

    cond do
      proto = meta[:protocol] -> to_string(proto)
      label = meta[:label] -> to_string(label)
      true -> ""
    end
  end

  @doc """
  Renders the data flows in a threat model to a Mermaid sequence diagram string.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = Choreo.ThreatModel.add_external_entity(model, :user, label: "Customer")
      iex> model = Choreo.ThreatModel.add_process(model, :web_api, label: "Web API")
      iex> model = Choreo.ThreatModel.data_flow(model, :user, :web_api, label: "HTTPS login")
      iex> Choreo.ThreatModel.Render.Mermaid.to_sequence(model)
      "sequenceDiagram\\n    actor user as Customer\\n    participant web_api as Web API\\n    user->>web_api: HTTPS login\\n"
  """
  @spec to_sequence(ThreatModel.t(), keyword()) :: String.t()
  def to_sequence(%ThreatModel{} = model, _opts \\ []) do
    nodes_decl =
      model.graph.nodes
      |> Enum.sort_by(fn {id, _node_data} -> id end)
      |> Enum.map_join("\n", fn {id, node_data} ->
        label = Map.get(node_data, :label, to_string(id))
        type = Map.get(node_data, :element_type, :process)
        m_id = mermaid_id(id)

        case type do
          :external_entity ->
            "    actor #{m_id} as #{label}"

          _ ->
            "    participant #{m_id} as #{label}"
        end
      end)

    flows_decl =
      ThreatModel.edges_with_meta(model)
      |> Enum.sort_by(fn {from, to, _weight, _meta} -> {from, to} end)
      |> Enum.map_join("\n", fn {from, to, _weight, meta} ->
        label =
          cond do
            is_binary(meta[:label]) and meta[:label] != "" -> meta[:label]
            meta[:protocol] -> to_string(meta[:protocol])
            true -> "flow"
          end

        crosses = ThreatModel.crosses_boundary?(model, from, to)
        encrypted = Map.get(meta, :encrypted, false)

        arrow =
          if crosses and not encrypted do
            "-->"
          else
            "->>"
          end

        "    #{mermaid_id(from)}#{arrow}#{mermaid_id(to)}: #{label}"
      end)

    """
    sequenceDiagram
    #{nodes_decl}
    #{flows_decl}
    """
  end

  defp mermaid_id(id) do
    str =
      cond do
        is_atom(id) -> Atom.to_string(id)
        is_binary(id) -> id
        true -> inspect(id)
      end

    if str =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/ do
      str
    else
      sanitized = String.replace(str, ~r/[^a-zA-Z0-9_]/, "_")

      if sanitized =~ ~r/^[0-9]/ do
        "s_" <> sanitized
      else
        sanitized
      end
    end
  end
end
