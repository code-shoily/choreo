defmodule Choreo.Sequence.Render.Mermaid do
  @moduledoc """
  Mermaid `sequenceDiagram` renderer for `Choreo.Sequence`.

  Mermaid is the natural home for sequence diagrams, so this renderer uses
  native sequence-diagram syntax rather than flowchart syntax.
  """

  alias Choreo.Render.Mermaid, as: MermaidRender
  alias Choreo.Sequence
  alias Choreo.Theme

  @doc """
  Renders a `Choreo.Sequence` as a Mermaid `sequenceDiagram`.
  """
  @spec to_mermaid(Sequence.t(), keyword()) :: String.t()
  def to_mermaid(%Sequence{} = seq, opts \\ []) do
    theme = theme(Keyword.get(opts, :theme, :default))

    theme_directives =
      if Keyword.has_key?(opts, :theme) do
        [render_theme_directive(theme)]
      else
        []
      end

    header = "sequenceDiagram"

    labels = Sequence.participant_labels(seq)
    id_map = MermaidRender.native_id_map(Sequence.participants(seq), "participant")

    participants =
      seq
      |> Sequence.participants()
      |> Enum.map(&render_participant(&1, labels, id_map, seq))

    body =
      seq
      |> Sequence.events()
      |> Enum.map(&render_event(&1, seq.edge_meta, labels, id_map))

    (theme_directives ++ [header] ++ participants ++ body)
    |> Enum.join("\n")
    |> String.trim_trailing()
  end

  defp render_participant(id, labels, id_map, seq) do
    label = MermaidRender.native_label(labels[id] || Macro.camelize(Atom.to_string(id)))
    safe_id = Map.fetch!(id_map, id)
    meta = Sequence.participant(seq, id) || %{}
    kind = meta[:node_type] || :participant

    prefix =
      case kind do
        :actor -> "    actor "
        :participant -> "    participant "
      end

    "#{prefix}#{safe_id} as #{label}"
  end

  defp render_event(%{type: :message, edge_id: eid}, edge_meta, _labels, id_map) do
    meta = Map.get(edge_meta, eid, %{})
    from = meta[:from]
    to = meta[:to]

    from_label = Map.fetch!(id_map, from)
    to_label = Map.fetch!(id_map, to)

    arrow =
      case meta[:type] do
        :async -> "-)"
        :return -> "-->>"
        :self -> "->>"
        _ -> "->>"
      end

    label = if meta[:label], do: ": #{MermaidRender.native_label(meta[:label])}", else: ""
    "    #{from_label}#{arrow}#{to_label}#{label}"
  end

  defp render_event(
         %{type: :activation, participant: p, action: action},
         _edge_meta,
         _labels,
         id_map
       ) do
    label = Map.fetch!(id_map, p)
    "    #{action} #{label}"
  end

  defp render_event(%{type: :note, position: pos, text: text}, _edge_meta, _labels, id_map) do
    {position_word, target} =
      case pos do
        {:over, id} ->
          {"over", Map.fetch!(id_map, id)}

        {:left, id} ->
          {"left of", Map.fetch!(id_map, id)}

        {:right, id} ->
          {"right of", Map.fetch!(id_map, id)}

        {:between, a, b} ->
          {"over", Map.fetch!(id_map, a) <> ", " <> Map.fetch!(id_map, b)}
      end

    sanitized = MermaidRender.native_label(text)
    "    Note #{position_word} #{target}: #{sanitized}"
  end

  defp render_event(
         %{type: :fragment, action: action, kind: kind, label: label},
         _edge_meta,
         _labels,
         _id_map
       )
       when action in [:start, :arm] do
    prefix = "    " <> Atom.to_string(kind)
    suffix = if label, do: " " <> MermaidRender.native_label(label), else: ""
    prefix <> suffix
  end

  defp render_event(%{type: :fragment, action: :end}, _edge_meta, _labels, _id_map) do
    "    end"
  end

  defp render_theme_directive(theme) do
    actor_bkg = theme.colors[:participant] || "#e8f4f8"
    actor_border = Choreo.Internal.darken(actor_bkg)
    actor_text = theme.node_fontcolor || "#334155"
    line_color = theme.edge_color || "#64748b"
    note_bkg = theme.colors[:note] || "#ffffcc"
    note_border = Choreo.Internal.darken(note_bkg)
    activation_bkg = theme.colors[:activation] || "#10b981"
    activation_border = Choreo.Internal.darken(activation_bkg)

    init_map = %{
      theme: "base",
      themeVariables: %{
        actorBkg: actor_bkg,
        actorBorder: actor_border,
        actorTextColor: actor_text,
        actorLineColor: line_color,
        signalColor: line_color,
        signalTextColor: actor_text,
        labelBoxBkgColor: note_bkg,
        labelBoxBorderColor: note_border,
        labelTextColor: actor_text,
        activationBkgColor: activation_bkg,
        activationBorderColor: activation_border
      }
    }

    "%%{init: #{Jason.encode!(init_map)}}%%"
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
