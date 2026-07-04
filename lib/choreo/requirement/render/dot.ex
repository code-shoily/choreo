defmodule Choreo.Requirement.Render.DOT do
  @moduledoc """
  Graphviz DOT rendering for `Choreo.Requirement` diagrams.

  Renders requirements as boxes colored by risk, components as rounded boxes,
  tests as stadiums, and stakeholders as circles. Relationship edges are
  labeled and styled by their type.
  """

  alias Choreo.Theme

  @doc """
  Renders a requirements diagram to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a
      `Choreo.Theme` struct
    * `:direction` — `:tb` (default), `:td` (alias for `:tb`), `:lr`, `:bt`, `:rl`

  ## Examples

      iex> req = Choreo.Requirement.new() |> Choreo.Requirement.add_requirement(:a, id: "R1", text: "A")
      iex> dot = Choreo.Requirement.Render.DOT.to_dot(req)
      iex> String.contains?(dot, "digraph")
      true
  """
  @spec to_dot(Choreo.Requirement.t(), keyword()) :: String.t()
  def to_dot(%Choreo.Requirement{} = req, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :tb) |> normalize_direction()

    id_map = build_id_map(req)
    graph = Choreo.Internal.make_multi_graph_safe(req.graph, id_map)

    base_opts =
      Yog.Render.DOT.default_options()
      |> Map.put(:rankdir, direction)
      |> Map.put(:splines, :spline)
      |> Map.put(:nodesep, 0.6)
      |> Map.put(:ranksep, 1.2)
      |> Map.put(:node_shape, :box)
      |> Map.put(:node_style, :filled)
      |> Map.put(:node_fontname, theme.node_fontname)
      |> Map.put(:node_fontsize, theme.node_fontsize)
      |> Map.put(:node_fontcolor, theme.node_fontcolor)
      |> Map.put(:edge_color, theme.edge_color)
      |> Map.put(:edge_fontname, theme.edge_fontname)
      |> Map.put(:edge_fontsize, theme.edge_fontsize)
      |> Map.put(:edge_penwidth, theme.edge_penwidth)
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(req, edge_id, id_map) end)
      |> Map.put(:node_attributes, node_attributes_fn(theme))
      |> Map.put(:edge_attributes, edge_attributes_fn(req, theme))
      |> Map.merge(Map.new(Keyword.drop(opts, [:theme, :direction])))

    Yog.Multi.DOT.to_dot(graph, base_opts)
  end

  @doc """
  Returns a theme for `Choreo.Requirement` DOT diagrams.
  """
  @spec theme(atom(), keyword()) :: Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  # ============================================================================
  # Direction normalization
  # ============================================================================

  defp normalize_direction(:td), do: :tb
  defp normalize_direction(dir) when dir in [:tb, :lr, :bt, :rl], do: dir
  defp normalize_direction(_), do: :tb

  # ============================================================================
  # Theme resolution
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_theme()
  defp resolve_theme(:dark), do: dark_theme()
  defp resolve_theme(:warm), do: warm_theme()
  defp resolve_theme(:forest), do: forest_theme()
  defp resolve_theme(:ocean), do: ocean_theme()
  defp resolve_theme(_), do: default_theme()

  defp default_theme do
    %Theme{
      name: :requirement_default,
      colors: %{
        requirement: "#f59e0b",
        component: "#3b82f6",
        test: "#10b981",
        stakeholder: "#8b5cf6",
        low: "#22c55e",
        medium: "#eab308",
        high: "#f97316",
        critical: "#ef4444"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0
    }
  end

  defp dark_theme do
    %Theme{
      default_theme()
      | name: :requirement_dark,
        node_fontcolor: "#e2e8f0",
        edge_color: "#94a3b8",
        graph_bgcolor: "#0f172a"
    }
  end

  defp warm_theme do
    %Theme{
      default_theme()
      | name: :requirement_warm,
        colors: %{
          requirement: "#f97316",
          component: "#ec4899",
          test: "#fbbf24",
          stakeholder: "#fdba74",
          low: "#86efac",
          medium: "#fde047",
          high: "#fb923c",
          critical: "#f87171"
        },
        edge_color: "#78716c"
    }
  end

  defp forest_theme do
    %Theme{
      default_theme()
      | name: :requirement_forest,
        colors: %{
          requirement: "#15803d",
          component: "#166534",
          test: "#65a30d",
          stakeholder: "#86efac",
          low: "#86efac",
          medium: "#d9f99d",
          high: "#facc15",
          critical: "#f87171"
        },
        edge_color: "#4b5563"
    }
  end

  defp ocean_theme do
    %Theme{
      default_theme()
      | name: :requirement_ocean,
        colors: %{
          requirement: "#1d4ed8",
          component: "#0284c7",
          test: "#0ea5e9",
          stakeholder: "#7dd3fc",
          low: "#86efac",
          medium: "#fde047",
          high: "#fb923c",
          critical: "#f87171"
        },
        edge_color: "#64748b"
    }
  end

  # ============================================================================
  # ID mapping
  # ============================================================================

  defp build_id_map(req) do
    req.graph.nodes
    |> Map.keys()
    |> Enum.map(&{&1, Choreo.Internal.dot_id(&1)})
    |> Map.new()
  end

  # ============================================================================
  # Node rendering
  # ============================================================================

  defp node_label(_id, data) do
    case data[:node_type] do
      :requirement ->
        text = data[:text] || ""
        req_id = data[:id] || ""
        if req_id != "", do: "#{req_id}\\n#{text}", else: text

      _ ->
        data[:label] || ""
    end
  end

  defp node_attributes_fn(theme) do
    fn _id, data ->
      type = Map.get(data, :node_type, :requirement)

      fill =
        if type == :requirement do
          risk_color(theme, data[:risk])
        else
          Theme.color(theme, type)
        end

      stroke = Choreo.Internal.darken(fill)

      [
        {:fillcolor, fill},
        {:color, stroke},
        {:shape, node_shape(type)},
        {:fontcolor, font_color(fill, theme)},
        {:style, "filled"}
      ]
    end
  end

  defp node_shape(:requirement), do: :box
  defp node_shape(:component), do: :roundedbox
  defp node_shape(:test), do: :stadium
  defp node_shape(:stakeholder), do: :circle
  defp node_shape(_), do: :box

  defp risk_color(theme, risk) do
    Map.get(theme.colors, risk, theme.colors[:requirement])
  end

  defp font_color(fill, theme) do
    if light_color?(fill), do: "#1e293b", else: theme.node_fontcolor
  end

  defp light_color?(hex) when is_binary(hex) do
    clean_hex = String.replace(hex, "#", "")

    case Base.decode16(String.upcase(clean_hex)) do
      {:ok, <<r, g, b>>} ->
        0.299 * r + 0.587 * g + 0.114 * b > 150.0

      _ ->
        false
    end
  end

  # ============================================================================
  # Edge rendering
  # ============================================================================

  defp edge_label(req, edge_id, _id_map) do
    meta = Map.get(req.edge_meta, edge_id, %{})
    meta[:label] || to_string(meta[:type] || "")
  end

  defp edge_attributes_fn(req, theme) do
    fn _from, _to, edge_id, _weight ->
      meta = Map.get(req.edge_meta, edge_id, %{})

      color =
        case meta[:type] do
          :satisfies -> "#10b981"
          :verifies -> "#3b82f6"
          :refines -> "#8b5cf6"
          :depends -> "#ef4444"
          :contains -> "#f59e0b"
          :derives -> "#06b6d4"
          :traces -> theme.edge_color
          _ -> theme.edge_color
        end

      style =
        case meta[:type] do
          :traces -> "dashed"
          :depends -> "dashed"
          _ -> "solid"
        end

      [
        {:color, color},
        {:fontcolor, color},
        {:style, style},
        {:penwidth, "1.5"}
      ]
    end
  end
end
