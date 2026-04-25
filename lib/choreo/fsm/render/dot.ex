defmodule Choreo.FSM.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.FSM` state-machine diagrams.

  Produces classic state-machine visualisation:

  * **Normal states** — filled circles
  * **Initial states** — filled circles with a black entry-point dot
  * **Final states** — double circles
  * **Transitions** — labeled arrows
  * Layout is left-to-right by default

  ## Themes

    * `:default` — light grey states, dark text, left-to-right
    * `:dark` — dark background, neon accents
    * `Choreo.Theme` struct — full custom control
  """

  alias Choreo.FSM
  alias Choreo.Theme

  @doc """
  Renders an FSM to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

  ## Examples

      dot = Choreo.FSM.Render.DOT.to_dot(fsm)
      dot = Choreo.FSM.Render.DOT.to_dot(fsm, theme: :dark)
  """
  @spec to_dot(Choreo.FSM.t(), keyword()) :: String.t()
  def to_dot(%Choreo.FSM{} = fsm, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    base_opts =
      Yog.Render.DOT.default_options()
      |> Map.put(:rankdir, :lr)
      |> Map.put(:splines, :spline)
      |> Map.put(:nodesep, 0.5)
      |> Map.put(:ranksep, 1.0)
      |> Map.put(:node_shape, :circle)
      |> Map.put(:node_style, :filled)
      |> Map.put(:node_color, fsm_color(theme, :normal))
      |> Map.put(:node_fontname, theme.node_fontname)
      |> Map.put(:node_fontsize, theme.node_fontsize)
      |> Map.put(:node_fontcolor, theme.node_fontcolor)
      |> Map.put(:edge_color, theme.edge_color)
      |> Map.put(:edge_fontname, theme.edge_fontname)
      |> Map.put(:edge_fontsize, theme.edge_fontsize)
      |> Map.put(:edge_penwidth, theme.edge_penwidth)
      |> Map.put(:arrowhead, :normal)
      |> Map.put(:node_label, fn _id, data -> data[:label] || "" end)
      |> Map.put(:edge_label, fn weight -> weight || "" end)
      |> Map.put(:node_attributes, node_attributes_fn(theme))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    dot = Yog.Render.DOT.to_dot(fsm.graph, base_opts)

    # Inject invisible entry-point nodes for initial states
    initial_nodes = build_initial_nodes(fsm)

    if initial_nodes != "" do
      inject_before_closing(dot, initial_nodes)
    else
      dot
    end
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_fsm_theme()
  defp resolve_theme(:dark), do: dark_fsm_theme()
  defp resolve_theme(_), do: default_fsm_theme()

  defp default_fsm_theme do
    %Theme{
      name: :fsm_default,
      colors: %{
        normal: "#e2e8f0",
        initial: "#10b981",
        final: "#e2e8f0"
      },
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
      colors: %{
        normal: "#1e293b",
        initial: "#10b981",
        final: "#1e293b"
      },
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

  defp theme_graph_overrides(%Theme{graph_bgcolor: nil}), do: %{}

  defp theme_graph_overrides(%Theme{graph_bgcolor: bg}) do
    %{bgcolor: bg}
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme) do
    fn _id, data ->
      case Map.get(data, :state_type, :normal) do
        :initial ->
          [
            {:fillcolor, fsm_color(theme, :initial)},
            {:fontcolor, "white"}
          ]

        :final ->
          [
            {:shape, :doublecircle},
            {:fillcolor, fsm_color(theme, :final)},
            {:penwidth, 2.0}
          ]

        _ ->
          [
            {:fillcolor, fsm_color(theme, :normal)}
          ]
      end
    end
  end

  # ============================================================================
  # Initial-state entry points
  # ============================================================================

  defp build_initial_nodes(fsm) do
    fsm
    |> FSM.initial_states()
    |> Enum.map_join("\n", fn id ->
      start_id = "__start_#{safe_id(id)}"
      target = safe_id(id)

      "  #{start_id} [shape=point, width=0.15, height=0.15, style=filled, fillcolor=black];\n" <>
        "  #{start_id} -> #{target};"
    end)
  end

  defp inject_before_closing(dot, extra) do
    String.replace(dot, ~r/\n\}\z/, "\n#{extra}\n}")
  end

  defp safe_id(id) when is_atom(id), do: Atom.to_string(id)
  defp safe_id(id) when is_binary(id), do: id
  defp safe_id(id), do: inspect(id)
end
