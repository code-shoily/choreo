defmodule Choreo.RenderScript do
  @moduledoc false

  @type target :: :mermaid | :dot
  @type artifact :: %{name: String.t(), model: struct(), opts: keyword()}

  @doc false
  @spec eval_file(Path.t()) :: any()
  def eval_file(path) when is_binary(path) do
    path
    |> Code.eval_file()
    |> elem(0)
  end

  @doc false
  @spec normalize(any(), keyword()) :: [artifact()]
  def normalize(value, opts \\ []) do
    default_name = opts |> Keyword.fetch!(:default_name) |> artifact_name!()

    value
    |> do_normalize(default_name)
    |> maybe_filter(Keyword.get(opts, :only))
  end

  @doc false
  @spec render_artifact(artifact(), target()) :: String.t()
  def render_artifact(%{model: model, opts: opts}, :mermaid), do: Choreo.to_mermaid(model, opts)
  def render_artifact(%{model: model, opts: opts}, :dot), do: Choreo.to_dot(model, opts)

  @doc false
  @spec extension(target()) :: String.t()
  def extension(:mermaid), do: ".mmd"
  def extension(:dot), do: ".dot"

  @doc false
  @spec parse_target(String.t() | nil) :: target()
  def parse_target(nil), do: :mermaid
  def parse_target("mermaid"), do: :mermaid
  def parse_target("mmd"), do: :mermaid
  def parse_target("dot"), do: :dot

  def parse_target(other) do
    raise ArgumentError, "unsupported render target #{inspect(other)}; expected mermaid or dot"
  end

  @doc false
  @spec output_path(artifact(), target(), Path.t(), single?: boolean()) :: Path.t()
  def output_path(%{name: name}, target, out, single?: single?) do
    cond do
      output_directory?(out) ->
        Path.join(out, name <> extension(target))

      single? ->
        out

      true ->
        raise ArgumentError,
              "multiple artifacts require --out to be a directory, got #{inspect(out)}"
    end
  end

  @doc false
  @spec default_name(Path.t()) :: String.t()
  def default_name(path) do
    path
    |> Path.basename()
    |> String.replace_suffix(".choreo.exs", "")
    |> String.replace_suffix(".exs", "")
    |> String.replace_suffix(".ex", "")
    |> artifact_name!()
  end

  defp do_normalize(%_struct{} = model, default_name),
    do: [%{name: default_name, model: model, opts: []}]

  defp do_normalize(%{} = map, _default_name) do
    map
    |> Enum.map(fn {name, value} -> artifact_from_named_value(name, value) end)
    |> Enum.sort_by(& &1.name)
  end

  defp do_normalize(value, default_name) when is_list(value) do
    if Keyword.keyword?(value) do
      value
      |> Enum.reduce(%{}, fn {name, artifact_value}, acc ->
        Map.put(acc, artifact_name!(name), artifact_value)
      end)
      |> do_normalize(default_name)
    else
      invalid_return!(value)
    end
  end

  defp do_normalize({model, opts}, default_name) when is_list(opts) do
    if Keyword.keyword?(opts) do
      [%{name: default_name, model: model, opts: opts}]
    else
      invalid_artifact_value!(default_name, {model, opts})
    end
  end

  defp do_normalize(model, default_name), do: [%{name: default_name, model: model, opts: []}]

  defp artifact_from_named_value(name, {model, opts}) when is_list(opts) do
    name = artifact_name!(name)

    if Keyword.keyword?(opts) do
      %{name: name, model: model, opts: opts}
    else
      invalid_artifact_value!(name, {model, opts})
    end
  end

  defp artifact_from_named_value(name, model),
    do: %{name: artifact_name!(name), model: model, opts: []}

  defp maybe_filter(artifacts, nil), do: artifacts

  defp maybe_filter(artifacts, only) do
    requested = artifact_name!(only)
    selected = Enum.filter(artifacts, &(&1.name == requested))

    case selected do
      [] ->
        available = Enum.map_join(artifacts, ", ", & &1.name)

        raise ArgumentError,
              "artifact #{inspect(requested)} was not found; available artifacts: #{available}"

      _ ->
        selected
    end
  end

  defp artifact_name!(name) when is_atom(name), do: name |> Atom.to_string() |> artifact_name!()

  defp artifact_name!(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_.-]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> raise ArgumentError, "artifact names cannot be empty"
      safe -> safe
    end
  end

  defp artifact_name!(name) do
    raise ArgumentError, "artifact names must be atoms or strings, got #{inspect(name)}"
  end

  defp output_directory?(path), do: String.ends_with?(path, ["/", "\\"]) or File.dir?(path)

  defp invalid_return!(value) do
    raise ArgumentError,
          "expected render script to return a Choreo renderable struct, " <>
            "{struct, opts}, a map of name => struct | {struct, opts}, or a keyword list of name => struct | {struct, opts}; " <>
            "got #{inspect(value)}"
  end

  defp invalid_artifact_value!(name, value) do
    raise ArgumentError,
          "artifact #{inspect(name)} must be a Choreo renderable struct or {struct, keyword_opts}; " <>
            "got #{inspect(value)}"
  end
end
