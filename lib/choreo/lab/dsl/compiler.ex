defmodule Choreo.Lab.DSL.Compiler do
  @moduledoc """
  Shared helper functions for Choreo Lab DSL compilers.

  This module encapsulates AST parsing and utility operations used during macro expansion
  of the experimental diagram DSLs.
  """

  @doc """
  Unwraps a block or single statement into a list of statements.
  """
  @spec statements(Macro.t()) :: [Macro.t()]
  def statements({:__block__, _meta, list}), do: list
  def statements(nil), do: []
  def statements(single), do: [single]

  @doc """
  Pops trailing options (a keyword list) from an argument list.
  """
  @spec pop_trailing_opts([any()]) :: {keyword(), [any()]}
  def pop_trailing_opts(args) do
    case List.last(args) do
      last when is_list(last) ->
        if Keyword.keyword?(last), do: {last, Enum.drop(args, -1)}, else: {[], args}

      _other ->
        {[], args}
    end
  end

  @doc """
  Pops a `do` block from an argument list.
  """
  @spec pop_do_block([any()]) :: {Macro.t() | nil, [any()]}
  def pop_do_block(args) do
    case List.last(args) do
      last when is_list(last) ->
        if Keyword.keyword?(last) and Keyword.has_key?(last, :do) do
          block = Keyword.get(last, :do)

          case Keyword.delete(last, :do) do
            [] -> {block, Enum.drop(args, -1)}
            rest -> {block, List.replace_at(args, -1, rest)}
          end
        else
          {nil, args}
        end

      _other ->
        {nil, args}
    end
  end

  @doc """
  Derives a snake_case atom from a string or atom label.
  """
  @spec slug_atom(String.t() | atom()) :: atom()
  def slug_atom(label) do
    label
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> raise ArgumentError, "cannot derive a node id from an empty label"
      slug -> String.to_atom(slug)
    end
  end

  @doc """
  Extracts line metadata from an AST node.
  """
  @spec line_meta(Macro.t()) :: keyword()
  def line_meta({_name, meta, _args}) when is_list(meta), do: meta
  def line_meta(_other), do: []

  @doc """
  Formats a line number suffix for error messages.
  """
  @spec line_suffix(keyword()) :: String.t()
  def line_suffix(meta) when is_list(meta) do
    case Keyword.get(meta, :line) do
      nil -> ""
      line -> " (line #{line})"
    end
  end

  def line_suffix(_meta), do: ""

  @doc """
  Unwraps a pipeline of modifications.
  """
  @spec unwrap_pipe(Macro.t(), [Macro.t()]) :: {Macro.t(), [Macro.t()]}
  def unwrap_pipe({:|>, _meta, [left, right]}, acc), do: unwrap_pipe(left, [right | acc])
  def unwrap_pipe(base, acc), do: {base, acc}

  @doc """
  Extracts a `do` block from a constructor statement (assigned or inline).
  Returns `{block, stripped_statement}` or `{nil, nil}`.
  """
  @spec extract_do_block(Macro.t()) :: {Macro.t() | nil, Macro.t() | nil}
  def extract_do_block({:=, meta, [var, constructor]}) do
    case pop_do_block_from_call(constructor) do
      {block, stripped_constructor} when not is_nil(block) ->
        {block, {:=, meta, [var, stripped_constructor]}}

      _ ->
        {nil, nil}
    end
  end

  def extract_do_block(call) do
    case pop_do_block_from_call(call) do
      {block, stripped_call} when not is_nil(block) ->
        {block, stripped_call}

      _ ->
        {nil, nil}
    end
  end

  defp pop_do_block_from_call({name, meta, args}) when is_atom(name) and is_list(args) do
    case pop_do_block(args) do
      {block, stripped_args} when not is_nil(block) ->
        {block, {name, meta, stripped_args}}

      _ ->
        {nil, nil}
    end
  end

  defp pop_do_block_from_call(_other), do: {nil, nil}

  @doc """
  Recursively compiles all statements in a block using a provided processor function.
  """
  @spec compile_block_statements(Macro.t(), any(), (Macro.t(), any() -> {any(), any()})) ::
          {any(), any()}
  def compile_block_statements(block, env, process_statement_fn) do
    {steps_reversed, env} =
      block
      |> statements()
      |> Enum.reduce({[], env}, fn statement, {steps, env} ->
        {statement_steps, env} = process_statement_fn.(statement, env)
        {Enum.reverse(statement_steps, steps), env}
      end)

    {Enum.reverse(steps_reversed), env}
  end
end
