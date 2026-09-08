defmodule Choreo.JSON do
  @moduledoc false

  @missing_jason_error %{
    message:
      "Jason is required for JSON decoding. Add {:jason, \"~> 1.4\"} to your dependencies to use Choreo.MCP.",
    data: nil
  }

  def encode!(term, opts \\ []) do
    if Code.ensure_loaded?(Jason) and function_exported?(Jason, :encode!, 2) do
      :erlang.apply(Jason, :encode!, [term, opts])
    else
      encode_json!(term)
    end
  end

  def decode(data, opts \\ []) do
    if Code.ensure_loaded?(Jason) and function_exported?(Jason, :decode, 2) do
      :erlang.apply(Jason, :decode, [data, opts])
    else
      {:error, @missing_jason_error}
    end
  end

  defp encode_json!(value) when is_binary(value), do: encode_string(value)
  defp encode_json!(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp encode_json!(true), do: "true"
  defp encode_json!(false), do: "false"
  defp encode_json!(nil), do: "null"
  defp encode_json!(value) when is_atom(value), do: value |> Atom.to_string() |> encode_string()

  defp encode_json!(values) when is_list(values) do
    if Keyword.keyword?(values) do
      values |> Map.new() |> encode_json!()
    else
      "[" <> Enum.map_join(values, ",", &encode_json!/1) <> "]"
    end
  end

  defp encode_json!(%{} = map) do
    entries =
      Enum.map_join(map, ",", fn {key, value} ->
        encode_key(key) <> ":" <> encode_json!(value)
      end)

    "{" <> entries <> "}"
  end

  defp encode_json!(value) do
    raise ArgumentError, "cannot JSON encode #{inspect(value)} without Jason"
  end

  defp encode_key(key) when is_binary(key), do: encode_string(key)
  defp encode_key(key) when is_atom(key), do: key |> Atom.to_string() |> encode_string()
  defp encode_key(key), do: key |> to_string() |> encode_string()

  defp encode_string(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\b", "\\b")
      |> String.replace("\f", "\\f")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")
      |> escape_control_chars()

    "\"" <> escaped <> "\""
  end

  defp escape_control_chars(value) do
    value
    |> String.to_charlist()
    |> Enum.map_join(fn
      char when char < 0x20 -> "\\u" <> String.pad_leading(Integer.to_string(char, 16), 4, "0")
      char -> <<char::utf8>>
    end)
  end
end
