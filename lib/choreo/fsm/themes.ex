defmodule Choreo.FSM.Themes do
  @moduledoc false
  # Shared FSM theme definitions, used by both the DOT and Mermaid renderers.
  # Centralising here prevents the two renderers from drifting apart.

  alias Choreo.Theme

  @doc false
  def resolve(name_or_theme, overrides \\ [])
  def resolve(%Theme{} = theme, []), do: theme
  def resolve(%Theme{} = theme, overrides), do: Theme.override(theme, overrides)
  def resolve(:default, overrides), do: Theme.override(default(), overrides)
  def resolve(:dark, overrides), do: Theme.override(dark(), overrides)
  def resolve(:minimal, overrides), do: Theme.override(minimal(), overrides)
  def resolve(:warm, overrides), do: Theme.override(warm(), overrides)
  def resolve(:forest, overrides), do: Theme.override(forest(), overrides)
  def resolve(:ocean, overrides), do: Theme.override(ocean(), overrides)
  def resolve(_, overrides), do: Theme.override(default(), overrides)

  @doc false
  def default do
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

  @doc false
  def dark do
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

  @doc false
  def minimal do
    %Theme{default() | name: :fsm_minimal}
  end

  @doc false
  def warm do
    %Theme{
      name: :fsm_warm,
      colors: %{
        normal: "#fecdd3",
        initial: "#f43f5e",
        final: "#fda4af"
      },
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

  @doc false
  def forest do
    %Theme{
      name: :fsm_forest,
      colors: %{
        normal: "#dcfce7",
        initial: "#22c55e",
        final: "#86efac"
      },
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

  @doc false
  def ocean do
    %Theme{
      name: :fsm_ocean,
      colors: %{
        normal: "#e0f2fe",
        initial: "#0ea5e9",
        final: "#7dd3fc"
      },
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
end
