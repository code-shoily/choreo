defmodule Choreo.Sequence.Analysis do
  @moduledoc """
  Analysis helpers for `Choreo.Sequence` diagrams.
  """

  alias Choreo.Sequence

  @doc """
  Validates the sequence diagram and returns a list of issues.

  Each issue is a tuple of `{severity, message}` where severity is
  `:error` or `:warning`.
  """
  @spec validate(Sequence.t()) :: [{:error | :warning, String.t()}]
  def validate(%Sequence{} = seq) do
    []
    |> Kernel.++(missing_labels(seq))
    |> Kernel.++(unknown_participants(seq))
    |> Kernel.++(isolated_participant_issues(seq))
    |> Kernel.++(unbalanced_activations(seq))
    |> Kernel.++(unclosed_fragments(seq))
  end

  @doc """
  Returns participants that never send or receive a message.
  """
  @spec isolated_participants(Sequence.t()) :: [atom()]
  def isolated_participants(%Sequence{} = seq) do
    participants = MapSet.new(Sequence.participants(seq))

    connected =
      seq
      |> Sequence.messages()
      |> Enum.reduce(MapSet.new(), fn msg, acc ->
        acc |> MapSet.put(msg[:from]) |> MapSet.put(msg[:to])
      end)

    MapSet.difference(participants, connected) |> MapSet.to_list()
  end

  @spec isolated_participant_issues(Sequence.t()) :: [{:warning, String.t()}]
  defp isolated_participant_issues(%Sequence{} = seq) do
    seq
    |> isolated_participants()
    |> Enum.map(fn p ->
      {:warning, "Participant :#{p} is isolated (no messages)"}
    end)
  end

  @doc """
  Returns messages that are missing labels.
  """
  @spec missing_labels(Sequence.t()) :: [{:error, String.t()}]
  def missing_labels(%Sequence{} = seq) do
    seq
    |> Sequence.messages()
    |> Enum.filter(fn msg -> is_nil(msg[:label]) or msg[:label] == "" end)
    |> Enum.map(fn msg ->
      {:error, "Message #{msg.order} from #{msg[:from]} to #{msg[:to]} has no label"}
    end)
  end

  @doc """
  Returns events that reference unknown participants.
  """
  @spec unknown_participants(Sequence.t()) :: [{:error, String.t()}]
  def unknown_participants(%Sequence{} = seq) do
    known = MapSet.new(Sequence.participants(seq))

    seq
    |> Sequence.events()
    |> Enum.flat_map(fn ev ->
      refs =
        case ev.type do
          :message ->
            meta = Map.get(seq.edge_meta, ev.edge_id, %{})
            [{meta[:from], "sender"}, {meta[:to], "receiver"}]

          :activation ->
            [{ev.participant, "activation"}]

          :note ->
            ev.position
            |> note_participants()
            |> Enum.map(&{&1, "note"})

          _ ->
            []
        end

      Enum.flat_map(refs, fn
        {nil, _} ->
          []

        {id, role} ->
          if MapSet.member?(known, id) do
            []
          else
            [
              {:error,
               "#{String.capitalize(role)} at step #{ev.order} references unknown participant :#{id}"}
            ]
          end
      end)
    end)
  end

  @doc """
  Detects unbalanced activation boxes.

  Returns `{participant, imbalance}` where imbalance is positive if there
  are more activates than deactivates and negative if there are more
  deactivates than activates.
  """
  @spec unbalanced_activations(Sequence.t()) :: [{:warning, String.t()}]
  def unbalanced_activations(%Sequence{events: events}) do
    events
    |> Enum.filter(&(&1.type == :activation))
    |> Enum.group_by(& &1.participant)
    |> Enum.map(fn {p, acts} ->
      bal =
        Enum.reduce(acts, 0, fn ev, acc ->
          if ev.action == :activate, do: acc + 1, else: acc - 1
        end)

      {p, bal}
    end)
    |> Enum.reject(fn {_, bal} -> bal == 0 end)
    |> Enum.map(fn {p, bal} ->
      if bal > 0 do
        {:warning, "Participant :#{p} has #{bal} unclosed activation(s)"}
      else
        {:warning, "Participant :#{p} has #{abs(bal)} unmatched deactivate(s)"}
      end
    end)
  end

  @doc """
  Detects fragments that were opened but never closed.
  """
  @spec unclosed_fragments(Sequence.t()) :: [{:error, String.t()}]
  def unclosed_fragments(%Sequence{events: events}) do
    {issues, depth} =
      events
      |> Enum.reverse()
      |> Enum.filter(&(&1.type == :fragment))
      |> Enum.reduce({[], 0}, fn ev, {issues, depth} ->
        case ev.action do
          :start ->
            {issues, depth + 1}

          :arm ->
            {issues, depth}

          :end ->
            if depth > 0 do
              {issues, depth - 1}
            else
              {[{:error, "Unexpected end of fragment at step #{ev.order}"} | issues], 0}
            end
        end
      end)

    if depth > 0 do
      [{:error, "#{depth} fragment(s) left unclosed"} | issues]
    else
      issues
    end
  end

  defp note_participants({:over, id}), do: [id]
  defp note_participants({:left, id}), do: [id]
  defp note_participants({:right, id}), do: [id]
  defp note_participants({:between, a, b}), do: [a, b]
end
