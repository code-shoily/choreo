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

  @doc """
  Renders a `Choreo.Sequence` as a DOT graph.
  """
  @spec to_dot(Sequence.t(), keyword()) :: String.t()
  def to_dot(%Sequence{} = seq, _opts \\ []) do
    labels = Sequence.participant_labels(seq)
    parts = Sequence.participants(seq)
    messages = Sequence.messages(seq)

    participant_nodes = Enum.map(parts, &render_participant_node(&1, labels))

    message_nodes_and_edges =
      messages
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {msg, idx} ->
        render_message_step(msg, idx, labels)
      end)

    activation_nodes = render_activations(seq, labels)

    body =
      (participant_nodes ++ message_nodes_and_edges ++ activation_nodes)
      |> Enum.map_join("\n", &"    #{&1}")

    """
    digraph SequenceDiagram {
        rankdir=TB;
        node [shape=box, style=rounded, fontname="Helvetica"];
        edge [fontname="Helvetica", fontsize=10];

    #{body}
    }
    """
    |> String.trim_trailing()
  end

  defp render_participant_node(id, labels) do
    label = labels[id] || to_string(id)
    "\"#{id}\" [label=\"#{label}\", style=filled, fillcolor=\"#e8f4f8\"];"
  end

  defp render_message_step(msg, idx, _labels) do
    from = msg[:from]
    to = msg[:to]
    label = msg[:label] || ""
    type = msg[:type]

    step_id = "step_#{idx}"
    step_label = "#{idx}. #{label}"

    from_node = "\"#{from}\""
    to_node = "\"#{to}\""

    step_node = "\"#{step_id}\" [label=\"#{step_label}\", shape=ellipse, fillcolor=\"#fff\"];"

    incoming =
      if from == to do
        ["#{from_node} -> \"#{step_id}\" [label=\"self\", style=dashed];"]
      else
        style = if type in [:async, :return], do: "dashed", else: "solid"

        [
          "#{from_node} -> \"#{step_id}\" [style=#{style}];",
          "\"#{step_id}\" -> #{to_node};"
        ]
      end

    [step_node | incoming]
  end

  defp render_activations(%Sequence{events: events}, labels) do
    events
    |> Enum.filter(&(&1.type == :activation))
    |> Enum.map(fn ev ->
      label = labels[ev.participant] || to_string(ev.participant)
      action = if ev.action == :activate, do: "+", else: "-"
      "\"note_#{ev.order}\" [label=\"#{action} #{label}\", shape=note, fillcolor=\"#ffffcc\"];"
    end)
  end
end
