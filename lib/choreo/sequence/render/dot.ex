defmodule Choreo.Sequence.Render.DOT do
  @moduledoc """
  Best-effort DOT renderer for `Choreo.Sequence`.

  GraphViz has no native sequence-diagram concept, so this renderer emits a
  left-to-right timeline view: participants appear at the top, messages flow
  downward through numbered steps. It is useful for embedding sequence traces
  in PDF or static image pipelines, but it is *not* a formal UML sequence
  diagram.
  """

  alias Choreo.Sequence
  alias Choreo.Theme

  @doc """
  Renders a `Choreo.Sequence` as a DOT graph.
  """
  @spec to_dot(Sequence.t(), keyword()) :: String.t()
  def to_dot(%Sequence{} = seq, opts \\ []) do
    theme = theme(Keyword.get(opts, :theme, :default))
    labels = Sequence.participant_labels(seq)
    parts = Sequence.participants(seq)
    messages = Sequence.messages(seq)

    participant_nodes = Enum.map(parts, &render_participant_node(&1, labels, seq, theme))

    message_nodes_and_edges =
      messages
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {msg, idx} ->
        render_message_step(msg, idx, labels, theme)
      end)

    activation_nodes = render_activations(seq, labels, theme)

    body =
      (participant_nodes ++ message_nodes_and_edges ++ activation_nodes)
      |> Enum.map_join("\n", &"    #{&1}")

    bgcolor_attr =
      if theme.graph_bgcolor, do: "    bgcolor=\"#{theme.graph_bgcolor}\";\n", else: ""

    """
    digraph SequenceDiagram {
        rankdir=TB;
    #{bgcolor_attr}    node [shape=box, style=rounded, fontname="#{theme.node_fontname}", fontsize=#{theme.node_fontsize}, fontcolor="#{theme.node_fontcolor}"];
        edge [fontname="#{theme.edge_fontname}", fontsize=#{theme.edge_fontsize}, color="#{theme.edge_color}", fontcolor="#{theme.node_fontcolor}"];

    #{body}
    }
    """
    |> String.trim_trailing()
  end

  defp render_participant_node(id, labels, seq, theme) do
    label = labels[id] || to_string(id)
    meta = Sequence.participant(seq, id) || %{}
    kind = meta[:node_type] || :participant
    fill = Map.get(theme.colors, kind, Map.get(theme.colors, :participant, "#e8f4f8"))
    stroke = Choreo.Internal.darken(fill)

    "\"#{id}\" [label=\"#{label}\", style=filled, fillcolor=\"#{fill}\", color=\"#{stroke}\", fontcolor=\"#{theme.node_fontcolor}\"];"
  end

  defp render_message_step(msg, idx, _labels, theme) do
    from = msg[:from]
    to = msg[:to]
    label = msg[:label] || ""
    type = msg[:type]

    step_id = "step_#{idx}"
    step_label = "#{idx}. #{label}"

    from_node = "\"#{from}\""
    to_node = "\"#{to}\""

    step_bg =
      if theme.name in [:sequence_dark, :planner_dark, :dark], do: "#1e293b", else: "#ffffff"

    step_stroke = theme.edge_color
    step_font = theme.node_fontcolor

    step_node =
      "\"#{step_id}\" [label=\"#{step_label}\", shape=ellipse, style=filled, fillcolor=\"#{step_bg}\", color=\"#{step_stroke}\", fontcolor=\"#{step_font}\"];"

    incoming =
      if from == to do
        [
          "#{from_node} -> \"#{step_id}\" [label=\"self\", style=dashed, color=\"#{theme.edge_color}\", fontcolor=\"#{theme.node_fontcolor}\"];"
        ]
      else
        style = if type in [:async, :return], do: "dashed", else: "solid"

        [
          "#{from_node} -> \"#{step_id}\" [style=#{style}, color=\"#{theme.edge_color}\", fontcolor=\"#{theme.node_fontcolor}\"];",
          "\"#{step_id}\" -> #{to_node} [color=\"#{theme.edge_color}\", fontcolor=\"#{theme.node_fontcolor}\"];"
        ]
      end

    [step_node | incoming]
  end

  defp render_activations(%Sequence{events: events}, labels, theme) do
    events
    |> Enum.filter(&(&1.type == :activation))
    |> Enum.map(fn ev ->
      label = labels[ev.participant] || to_string(ev.participant)
      action = if ev.action == :activate, do: "+", else: "-"
      fill = Map.get(theme.colors, :activation, "#ffffcc")
      stroke = Choreo.Internal.darken(fill)

      "\"note_#{ev.order}\" [label=\"#{action} #{label}\", shape=note, style=filled, fillcolor=\"#{fill}\", color=\"#{stroke}\", fontcolor=\"#{theme.node_fontcolor}\"];"
    end)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_sequence_theme()
  defp resolve_theme(:dark), do: dark_sequence_theme()
  defp resolve_theme(:minimal), do: minimal_sequence_theme()
  defp resolve_theme(:warm), do: warm_sequence_theme()
  defp resolve_theme(:forest), do: forest_sequence_theme()
  defp resolve_theme(:ocean), do: ocean_sequence_theme()
  defp resolve_theme(_), do: default_sequence_theme()

  defp minimal_sequence_theme do
    %Theme{default_sequence_theme() | name: :sequence_minimal}
  end

  defp default_sequence_theme do
    %Theme{
      name: :sequence_default,
      colors: %{actor: "#ef4444", participant: "#3b82f6", note: "#f59e0b", activation: "#10b981"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#334155",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      graph_bgcolor: nil
    }
  end

  defp dark_sequence_theme do
    %Theme{
      name: :sequence_dark,
      colors: %{actor: "#f472b6", participant: "#60a5fa", note: "#fb923c", activation: "#34d399"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#f1f5f9",
      edge_color: "#94a3b8",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      graph_bgcolor: "#0f172a"
    }
  end

  defp warm_sequence_theme do
    %Theme{
      name: :sequence_warm,
      colors: %{actor: "#ec4899", participant: "#f97316", note: "#eab308", activation: "#84cc16"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#451a03",
      edge_color: "#78716c",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      graph_bgcolor: "#fffbeb"
    }
  end

  defp forest_sequence_theme do
    %Theme{
      name: :sequence_forest,
      colors: %{actor: "#059669", participant: "#10b981", note: "#eab308", activation: "#65a30d"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#064e3b",
      edge_color: "#4b5563",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      graph_bgcolor: "#f0fdf4"
    }
  end

  defp ocean_sequence_theme do
    %Theme{
      name: :sequence_ocean,
      colors: %{actor: "#0284c7", participant: "#0ea5e9", note: "#f59e0b", activation: "#14b8a6"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#0c4a6e",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      graph_bgcolor: "#f0f9ff"
    }
  end
end
