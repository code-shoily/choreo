defmodule Choreo.FSM.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.FSM` state-machine diagrams.

  Produces classic state-machine visualisation:

  * **Normal states** — filled circles
  * **Initial states** — filled circles with a black entry-point dot
  * **Final states** — circles with thick stroke (double-circle equivalent)
  * **Transitions** — labeled arrows
  * Layout is left-to-right by default

  ## Themes

    * `:default` — light grey states, dark text, left-to-right
    * `:dark` — dark background, neon accents
    * `Choreo.Theme` struct — full custom control

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_state(:a)
      iex> mermaid = Choreo.FSM.Render.Mermaid.to_mermaid(fsm)
      iex> String.contains?(mermaid, "graph LR")
      true
      iex> String.contains?(mermaid, "a")
      true
  """

  alias Choreo.FSM
  alias Choreo.Theme

  @doc """
  Renders an FSM to a Mermaid flowchart string.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:lr` (default), `:td`, `:rl`, `:bt`
    * `:highlighted_nodes` — list of state IDs to highlight
    * `:highlighted_edges` — list of edge IDs or `{from, to}` tuples to highlight
    * Any other option accepted by `Yog.Multi.Mermaid.to_mermaid/2`
  """
  @spec to_mermaid(FSM.t(), keyword()) :: String.t()
  def to_mermaid(%FSM{} = fsm, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :lr)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    graph = build_mermaid_graph(fsm)

    base =
      Yog.Multi.Mermaid.default_options()
      |> Map.put(:node_label, fn _id, data ->
        if data[:label] == "", do: " ", else: data[:label] || ""
      end)
      |> Map.put(:edge_label, fn _edge_id, weight -> weight || "" end)
      |> Map.put(:node_shape, :circle)
      |> Map.put(:node_attributes, node_attributes_fn(theme, fsm, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(theme, hl_edges))
      |> Map.put(:direction, direction)
      |> Map.put(:default_font_color, theme.node_fontcolor)
      |> Map.put(:default_link_stroke, theme.edge_color)
      |> Map.merge(Map.new(opts))

    Yog.Multi.Mermaid.to_mermaid(graph, base)
  end

  @doc """
  Returns a theme for `Choreo.FSM` Mermaid diagrams.
  """
  @spec theme(atom(), keyword()) :: Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_fsm_theme()
  defp resolve_theme(:dark), do: dark_fsm_theme()
  defp resolve_theme(:warm), do: warm_fsm_theme()
  defp resolve_theme(:forest), do: forest_fsm_theme()
  defp resolve_theme(:ocean), do: ocean_fsm_theme()
  defp resolve_theme(_), do: default_fsm_theme()

  defp warm_fsm_theme do
    %Theme{
      name: :fsm_warm,
      colors: %{normal: "#fecdd3", initial: "#f43f5e", final: "#fda4af"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#1e293b",
      edge_color: "#78716c",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#fef2f2"
    }
  end

  defp forest_fsm_theme do
    %Theme{
      name: :fsm_forest,
      colors: %{normal: "#dcfce7", initial: "#22c55e", final: "#86efac"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#1e293b",
      edge_color: "#4b5563",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0fdf4"
    }
  end

  defp ocean_fsm_theme do
    %Theme{
      name: :fsm_ocean,
      colors: %{normal: "#e0f2fe", initial: "#0ea5e9", final: "#7dd3fc"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#1e293b",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0f9ff"
    }
  end

  defp default_fsm_theme do
    %Theme{
      name: :fsm_default,
      colors: %{normal: "#e2e8f0", initial: "#10b981", final: "#e2e8f0"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#1e293b",
      edge_color: "#475569",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: nil
    }
  end

  defp dark_fsm_theme do
    %Theme{
      name: :fsm_dark,
      colors: %{normal: "#1e293b", initial: "#10b981", final: "#1e293b"},
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

  defp fsm_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#e2e8f0")
  end

  # ============================================================================
  # Graph builder — injects entry-point nodes for initial states
  # ============================================================================

  defp build_mermaid_graph(fsm) do
    initial_states = FSM.initial_states(fsm) |> MapSet.to_list()

    if initial_states == [] do
      fsm.graph
    else
      entry_nodes =
        initial_states
        |> Enum.map(fn id ->
          entry_id = :"__start_#{id}"
          {entry_id, %{label: "", type: :entry_point}}
        end)
        |> Map.new()

      entry_edges =
        initial_states
        |> Enum.with_index()
        |> Enum.map(fn {id, idx} ->
          entry_id = :"__start_#{id}"
          {:"__entry_#{idx}", {entry_id, id, nil}}
        end)
        |> Map.new()

      nodes = Map.merge(fsm.graph.nodes, entry_nodes)
      edges = Map.merge(fsm.graph.edges, entry_edges)

      %{fsm.graph | nodes: nodes, edges: edges}
    end
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme, fsm, hl_nodes) do
    fn id, data ->
      if data[:type] == :entry_point do
        [{:fill, "black"}, {:stroke, "black"}, {:stroke_width, "1px"}]
      else
        is_initial = id in FSM.initial_states(fsm)
        is_final = id in FSM.final_states(fsm)

        base =
          cond do
            is_initial and is_final ->
              [
                {:fill, fsm_color(theme, :initial)},
                {:stroke, Choreo.Internal.darken(fsm_color(theme, :initial))},
                {:stroke_width, "3px"}
              ]

            is_initial ->
              [
                {:fill, fsm_color(theme, :initial)},
                {:stroke, Choreo.Internal.darken(fsm_color(theme, :initial))}
              ]

            is_final ->
              [
                {:fill, fsm_color(theme, :final)},
                {:stroke, Choreo.Internal.darken(fsm_color(theme, :final))},
                {:stroke_width, "3px"}
              ]

            true ->
              [
                {:fill, fsm_color(theme, :normal)},
                {:stroke, Choreo.Internal.darken(fsm_color(theme, :normal))}
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
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      base = [
        {:stroke, theme.edge_color},
        {:stroke_width, "#{theme.edge_penwidth}px"}
      ]

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
