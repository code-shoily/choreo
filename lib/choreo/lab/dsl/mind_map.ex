defmodule Choreo.Lab.DSL.MindMap do
  import Choreo.Lab.DSL.Compiler

  @moduledoc """
  Experimental Livebook-friendly DSL for sketching mind maps.

  This Lab DSL compiles to the stable, pipe-first `Choreo.MindMap` builders and
  returns an ordinary `%Choreo.MindMap{}`. It follows the shared Lab identity rule:
  in assignment form, the variable name becomes the node id and the string becomes
  the display label; in inline form, the string is slugged into an id and also used
  as the label.

  ## Examples

      iex> import Choreo.Lab.DSL.MindMap
      ...> map = mind_map do
      ...>   system = root("System Design")
      ...>   requirements = topic("Requirements")
      ...>   risks = note("Open Risks")
      ...>
      ...>   system ~> requirements
      ...>   edge requirements ~> risks, "needs review"
      ...> end
      iex> Choreo.MindMap.root(map)
      :system
      iex> map.graph.nodes[:requirements].label
      "Requirements"
      iex> map.edge_meta[{:requirements, :risks}].label
      "needs review"

  Branch edges can use `~>`, pipe modifiers, explicit `edge`, or the typed
  `branch` form:

      root ~> topic
      root ~> topic |> on("expands into")
      edge root ~> topic, "expands into"
      branch root ~> topic, "expands into"

  Associative cross-links use the typed `associate`/`association` form, a typed
  keyword on `edge`, or a pipe modifier:

      associate topic ~> note, "related"
      association topic ~> note, "related"
      edge topic ~> note, associate: "related"
      topic ~> note |> associate("related")
  """

  @type node_decl :: %{id: Yog.node_id(), builder: atom(), opts: keyword()}
  @type edge_decl :: %{
          from: Yog.node_id(),
          to: Yog.node_id(),
          edge_type: :branch | :associate,
          opts: keyword()
        }

  @node_verbs [:root, :topic, :subtopic, :note]

  @node_builders %{
    root: :set_root,
    topic: :add_topic,
    subtopic: :add_subtopic,
    note: :add_note
  }

  @doc """
  Returns the vocabulary supported by the mind-map DSL.

  This is meant as a lightweight Livebook discovery helper when autocomplete is
  not enough.

      iex> taxonomy = Choreo.Lab.DSL.MindMap.taxonomy()
      iex> :root in taxonomy.nodes
      true
      iex> :associate in taxonomy.edges
      true
      iex> :on in taxonomy.modifiers
      true
  """
  @spec taxonomy() :: %{
          nodes: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def taxonomy do
    %{
      nodes: @node_verbs,
      edges: [:~>, :edge, :branch, :associate, :association],
      modifiers: [:on, :label, :associate, :association],
      options: [:label, :with, :id, :branch, :associate, :association, :type]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: %{
          nodes: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.MindMap{}` from a compact Lab DSL block.
  """
  defmacro mind_map(do: block) do
    compile(block)
  end

  defmacro mind_map(opts, do: block) do
    compile(block, opts)
  end

  defp compile(block, opts \\ []) do
    {steps_reversed, _env} =
      block
      |> statements()
      |> Enum.reduce({[], %{}}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {Enum.reverse(statement_steps, steps), env}
      end)

    Enum.reduce(
      Enum.reverse(steps_reversed),
      quote(do: Choreo.MindMap.new(unquote(Macro.escape(opts)))),
      &pipe_step/2
    )
  end

  defp statement_steps({:=, meta, [{var, _, context}, constructor]}, env)
       when is_atom(var) and is_atom(context) do
    node = node_from_constructor(constructor, var, meta)
    {[{:node, node}], Map.put(env, var, node.id)}
  end

  defp statement_steps({:edge, meta, [edge_ast, label]}, env) when is_binary(label) do
    {edge, nodes} = edge_from_ast(edge_ast, [label: label], env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({:edge, meta, [edge_ast, opts]}, env) when is_list(opts) do
    {edge, nodes} = edge_from_ast(edge_ast, normalize_edge_opts(opts), env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({:edge, meta, [edge_ast]}, env) do
    {edge, nodes} = edge_from_ast(edge_ast, [], env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({name, meta, [edge_ast, label]}, env)
       when name in [:branch, :associate, :association] and is_binary(label) do
    {edge, nodes} = edge_from_ast(edge_ast, [type: edge_type(name), label: label], env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({name, meta, [edge_ast, opts]}, env)
       when name in [:branch, :associate, :association] and is_list(opts) do
    opts = opts |> normalize_edge_opts() |> Keyword.put(:type, edge_type(name))
    {edge, nodes} = edge_from_ast(edge_ast, opts, env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({name, meta, [edge_ast]}, env)
       when name in [:branch, :associate, :association] do
    {edge, nodes} = edge_from_ast(edge_ast, [type: edge_type(name)], env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({:|>, _meta, _args} = ast, env) do
    {edge, nodes} = edge_from_piped_ast(ast, env)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({:~>, meta, _args} = ast, env) do
    {edge, nodes} = edge_from_ast(ast, [], env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({name, meta, args} = ast, env) when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(ast, nil, meta)
      {[{:node, node}], env}
    else
      unsupported_statement!(ast, meta)
    end
  end

  defp statement_steps(other, _env), do: unsupported_statement!(other, nil)

  defp edge_declaration_steps(nodes, edge) do
    nodes
    |> Enum.reduce([{:edge, edge}], fn node, steps -> [{:node, node} | steps] end)
    |> Enum.reverse()
  end

  defp edge_from_piped_ast(ast, env) do
    {base, modifiers} = unwrap_pipe(ast, [])
    opts = modifiers |> Enum.reduce([], &modifier_opt/2) |> normalize_edge_opts()
    edge_from_ast(base, opts, env, line_meta(base))
  end

  defp modifier_opt({name, _meta, [value]}, acc) when name in [:on, :label] do
    Keyword.put(acc, :label, value)
  end

  defp modifier_opt({name, _meta, [value]}, acc) when name in [:associate, :association] do
    acc
    |> Keyword.put(:type, :associate)
    |> Keyword.put(:label, value)
  end

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported mind-map edge modifier: #{Macro.to_string(other)}; " <>
            "use `on(value)`, `label(value)`, or `associate(value)`"
  end

  defp edge_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, from_node} = endpoint_id(from_ast, env, meta)
    {to, to_node} = endpoint_id(to_ast, env, meta)
    nodes = [from_node, to_node] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)
    {edge_type, opts} = edge_type_and_opts(opts)

    {%{from: from, to: to, edge_type: edge_type, opts: opts}, nodes}
  end

  defp edge_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in mind-map DSL, got #{Macro.to_string(other)}" <>
            line_suffix(meta)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env, var) do
      {:ok, id} -> {id, nil}
      :error -> raise ArgumentError, "unknown mind-map node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, _env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, meta)
      {node.id, node}
    else
      raise ArgumentError, "unknown mind-map node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported mind-map edge endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `idea = root(\"Idea\")`"
  end

  defp node_from_constructor({name, meta, args}, var, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError, "unknown mind-map node constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    {id, opts} = node_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
  end

  defp node_from_constructor(other, _var, meta) do
    raise ArgumentError,
          "expected mind-map node constructor, got #{Macro.to_string(other)}#{line_suffix(meta)}"
  end

  defp node_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "mind-map node constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline mind-map node constructors need a label/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp maybe_put_label(opts, nil), do: opts

  defp maybe_put_label(opts, label) when is_binary(label),
    do: Keyword.put_new(opts, :label, label)

  defp maybe_put_label(opts, label) when is_atom(label),
    do: Keyword.put_new(opts, :label, to_string(label))

  defp maybe_put_label(opts, _other), do: opts

  defp id_from_label(id) when is_atom(id), do: id
  defp id_from_label(id) when is_binary(id), do: slug_atom(id)

  defp id_from_label(other) do
    raise ArgumentError,
          "inline mind-map node label/id must be a string or atom, got #{inspect(other)}"
  end

  defp normalize_edge_opts(opts) do
    opts
    |> normalize_label_alias(:with)
    |> normalize_label_alias(:branch)
    |> normalize_label_alias(:associate)
    |> normalize_label_alias(:association)
  end

  defp normalize_label_alias(opts, key) do
    {value, opts} = Keyword.pop(opts, key)

    cond do
      value == nil ->
        opts

      key == :branch ->
        opts |> Keyword.put_new(:type, :branch) |> Keyword.put_new(:label, value)

      key in [:associate, :association] ->
        opts |> Keyword.put_new(:type, :associate) |> Keyword.put_new(:label, value)

      true ->
        Keyword.put_new(opts, :label, value)
    end
  end

  defp edge_type_and_opts(opts) do
    {type, opts} = Keyword.pop(opts, :type)

    case type || :branch do
      :branch ->
        {:branch, opts}

      :associate ->
        {:associate, opts}

      :association ->
        {:associate, opts}

      other ->
        raise ArgumentError,
              "unsupported mind-map edge type #{inspect(other)}; use :branch or :associate"
    end
  end

  defp edge_type(:branch), do: :branch
  defp edge_type(:associate), do: :associate
  defp edge_type(:association), do: :associate

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.MindMap, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, edge_type: :branch, opts: opts}}, acc) do
    quote do
      Choreo.MindMap.branch(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, edge_type: :associate, opts: opts}}, acc) do
    quote do
      Choreo.MindMap.associate(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in mind-map DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
  end

  # Autocomplete helper stubs
  for verb <- [:associate, :association, :branch, :note, :root, :subtopic, :topic] do
    def unquote(verb)(_arg1 \\ nil, _arg2 \\ nil, _opts \\ []) do
      raise "DSL constructor `#{unquote(verb)}` must be called inside a DSL block"
    end
  end
end
