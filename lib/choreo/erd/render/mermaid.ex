defmodule Choreo.ERD.Render.Mermaid do
  @moduledoc """
  Mermaid.js native `erDiagram` renderer for `Choreo.ERD`.
  """

  @doc """
  Renders an ERD to Mermaid native erDiagram syntax.
  """
  @spec to_mermaid(Choreo.ERD.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.ERD{} = erd, _opts \\ []) do
    tables_part =
      erd.graph.nodes
      |> Enum.sort_by(fn {id, _data} -> id end)
      |> Enum.map_join("\n", fn {id, data} ->
        render_table(id, data)
      end)

    relations_part =
      erd.graph.edges
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map_join("\n", fn edge_id ->
        {from, to, _weight} = Map.get(erd.graph.edges, edge_id)
        meta = Map.get(erd.edge_meta, edge_id, %{})
        render_relationship(from, to, meta)
      end)

    "erDiagram\n" <> tables_part <> "\n" <> relations_part <> "\n"
  end

  defp render_table(id, data) do
    columns = data[:columns] || []

    column_lines =
      Enum.map_join(columns, "\n", fn col ->
        type_str = to_string(col[:type])
        name_str = to_string(col[:name])

        key_str =
          case col[:key] do
            :pk -> " PK"
            :fk -> " FK"
            _ -> ""
          end

        comment_str =
          if col[:comment], do: " \"#{col[:comment]}\"", else: ""

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
        :many_to_many -> "}|--|{"
        _ -> "||--||"
      end

    label = meta[:label] || "references"
    "  #{from} #{symbol} #{to} : \"#{label}\""
  end
end
