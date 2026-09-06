defmodule Choreo.ERD.Render.Mermaid do
  @moduledoc """
  Mermaid.js native `erDiagram` renderer for `Choreo.ERD`.
  """

  alias Choreo.Render.Mermaid, as: MermaidRender

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    Choreo.ERD.Render.DOT.theme(name, overrides)
  end

  @doc """
  Renders an ERD to Mermaid native erDiagram syntax.
  """
  @spec to_mermaid(Choreo.ERD.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.ERD{} = erd, _opts \\ []) do
    id_map = MermaidRender.native_id_map(Map.keys(erd.graph.nodes), "entity")

    tables_part =
      erd.graph.nodes
      |> Enum.sort_by(fn {id, _data} -> to_string(id) end)
      |> Enum.map_join("\n", fn {id, data} ->
        render_table(Map.fetch!(id_map, id), data)
      end)

    relations_part =
      erd.graph.edges
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map_join("\n", fn edge_id ->
        {from, to, _weight} = Map.get(erd.graph.edges, edge_id)
        meta = Map.get(erd.edge_meta, edge_id, %{})
        render_relationship(Map.fetch!(id_map, from), Map.fetch!(id_map, to), meta)
      end)

    "erDiagram\n" <> tables_part <> "\n" <> relations_part <> "\n"
  end

  defp render_table(id, data) do
    columns = data[:columns] || []

    column_lines =
      Enum.map_join(columns, "\n", fn col ->
        type_str = MermaidRender.native_token(col[:type])
        name_str = MermaidRender.native_token(col[:name])

        key_str =
          case col[:key] do
            :pk -> " PK"
            :fk -> " FK"
            _ -> ""
          end

        comment_str =
          if col[:comment],
            do: " \"#{MermaidRender.native_label(col[:comment])}\"",
            else: ""

        "    #{type_str} #{name_str}#{key_str}#{comment_str}"
      end)

    "  #{id} {\n" <> column_lines <> "\n  }"
  end

  defp render_relationship(from, to, meta) do
    symbol =
      case meta[:cardinality] do
        :one_to_one -> "||--||"
        :one_to_many -> "||--o{"
        :zero_or_one_to_many -> "|o--o{"
        :exactly_one_to_many -> "||--|{"
        :many_to_many -> "}o--o{"
        _ -> "||--||"
      end

    label = meta[:label] || "references"
    "  #{from} #{symbol} #{to} : \"#{MermaidRender.native_label(label)}\""
  end
end
