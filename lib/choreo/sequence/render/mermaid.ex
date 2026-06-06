defmodule Choreo.Sequence.Render.Mermaid do
  @moduledoc """
  Mermaid `sequenceDiagram` renderer for `Choreo.Sequence`.

  Mermaid is the natural home for sequence diagrams, so this renderer uses
  native sequence-diagram syntax rather than flowchart syntax.
  """

  alias Choreo.Sequence

  @doc """
  Renders a `Choreo.Sequence` as a Mermaid `sequenceDiagram`.
  """
  @spec to_mermaid(Sequence.t(), keyword()) :: String.t()
  def to_mermaid(%Sequence{} = seq, _opts \\ []) do
    header = "sequenceDiagram"

    labels = participant_labels(seq)

    participants =
      seq
      |> Sequence.participants()
      |> Enum.map(&render_participant(&1, seq.graph))

    body =
      seq
      |> Sequence.events()
      |> Enum.map(&render_event(&1, seq.edge_meta, labels))

    ([header] ++ participants ++ body)
    |> Enum.join("\n")
    |> String.trim_trailing()
  end

  defp participant_labels(%Sequence{graph: graph}) do
    Map.new(graph.nodes, fn {id, meta} ->
      label = meta[:label] || Macro.camelize(Atom.to_string(id))
      {id, label}
    end)
  end

  defp render_participant(id, graph) do
    meta = Map.get(graph.nodes, id) || %{}
    label = meta[:label] || Macro.camelize(Atom.to_string(id))
    kind = meta[:node_type] || :participant

    prefix =
      case kind do
        :actor -> "    actor "
        :participant -> "    participant "
      end

    prefix <> label
  end

  defp render_event(%{type: :message, edge_id: eid}, edge_meta, labels) do
    meta = Map.get(edge_meta, eid, %{})
    from = meta[:from]
    to = meta[:to]

    from_label = labels[from] || to_string(from)
    to_label = labels[to] || to_string(to)

    arrow =
      case meta[:type] do
        :async -> "-->>"
        :return -> "-->>"
        :self -> "->>"
        _ -> "->>"
      end

    label = if meta[:label], do: ": #{meta[:label]}", else: ""
    "    #{from_label}#{arrow}#{to_label}#{label}"
  end

  defp render_event(%{type: :activation, participant: p, action: action}, _edge_meta, labels) do
    label = labels[p] || to_string(p)
    "    #{action} #{label}"
  end

  defp render_event(%{type: :note, position: pos, text: text}, _edge_meta, labels) do
    {position_word, target} =
      case pos do
        {:over, id} ->
          {"over", labels[id] || to_string(id)}

        {:left, id} ->
          {"left of", labels[id] || to_string(id)}

        {:right, id} ->
          {"right of", labels[id] || to_string(id)}

        {:between, a, b} ->
          {"over", (labels[a] || to_string(a)) <> ", " <> (labels[b] || to_string(b))}
      end

    "    Note #{position_word} #{target}: #{text}"
  end

  defp render_event(
         %{type: :fragment, action: :start, kind: kind, label: label},
         _edge_meta,
         _labels
       ) do
    prefix = "    " <> Atom.to_string(kind)
    if label, do: "#{prefix} #{label}", else: prefix
  end

  defp render_event(%{type: :fragment, action: :end}, _edge_meta, _labels) do
    "    end"
  end
end
