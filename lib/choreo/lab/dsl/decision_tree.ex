defmodule Choreo.Lab.DSL.DecisionTree do
  import Choreo.Lab.DSL.Compiler

  @moduledoc """
  Experimental Livebook-friendly DSL for sketching decision trees.

  This Lab DSL compiles to the stable, pipe-first `Choreo.DecisionTree` builders
  and returns an ordinary `%Choreo.DecisionTree{}`. It is useful for interview
  decision policies, routing rules, fallback strategies, and tradeoff walkthroughs.

  ## Examples

      iex> import Choreo.Lab.DSL.DecisionTree
      ...> tree = decision_tree do
      ...>   traffic = root("Traffic Source", feature: "source")
      ...>   authenticated = decision("Authenticated?", feature: "auth")
      ...>   reject = outcome("Reject", class: "403")
      ...>   route = outcome("Route Request", class: "route")
      ...>
      ...>   traffic ~> authenticated |> when_("api")
      ...>   edge authenticated ~> reject, "no"
      ...>   branch authenticated ~> route, "yes"
      ...> end
      iex> Choreo.DecisionTree.root(tree)
      :traffic
      iex> Choreo.DecisionTree.condition(tree, :authenticated, :route)
      "yes"

  Branch conditions can use pipe modifiers or explicit branch forms:

      root ~> decision |> when_("api")
      decision ~> outcome |> condition("yes")
      edge decision ~> outcome, "yes"
      branch decision ~> outcome, "yes"
  """

  @type node_decl :: %{id: Yog.node_id(), builder: atom(), opts: keyword()}
  @type branch_decl :: %{from: Yog.node_id(), to: Yog.node_id(), condition: String.t()}

  @node_verbs [:root, :decision, :question, :outcome, :result, :leaf]

  @node_builders %{
    root: :set_root,
    decision: :add_decision,
    question: :add_decision,
    outcome: :add_outcome,
    result: :add_outcome,
    leaf: :add_outcome
  }

  @doc """
  Returns the vocabulary supported by the decision-tree DSL.

      iex> taxonomy = Choreo.Lab.DSL.DecisionTree.taxonomy()
      iex> :root in taxonomy.nodes
      true
      iex> :branch in taxonomy.edges
      true
      iex> :when_ in taxonomy.modifiers
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
      edges: [:~>, :edge, :branch],
      modifiers: [:when_, :condition, :on, :label, :branch, :edge],
      options: [:label, :with, :id, :feature, :class, :probability]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: map()
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.DecisionTree{}` from a compact Lab DSL block.
  """
  defmacro decision_tree(do: block), do: compile(block)
  defmacro decision_tree(opts, do: block), do: compile(block, opts)

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
      quote(do: Choreo.DecisionTree.new(unquote(Macro.escape(opts)))),
      &pipe_step/2
    )
  end

  defp statement_steps({:=, meta, [{var, _, context}, constructor]}, env)
       when is_atom(var) and is_atom(context) do
    node = node_from_constructor(constructor, var, meta)
    {[{:node, node}], Map.put(env, var, node.id)}
  end

  defp statement_steps({verb, meta, [edge_ast, condition, opts]}, env)
       when verb in [:edge, :branch] and is_list(opts) and not is_nil(condition) do
    cond_val =
      case Keyword.get(opts, :condition) do
        nil -> to_string(condition)
        c -> to_string(c)
      end

    {branch, nodes} = branch_from_ast(edge_ast, cond_val, opts, env, meta)
    {branch_declaration_steps(nodes, branch), env}
  end

  defp statement_steps({verb, meta, [edge_ast, condition]}, env)
       when verb in [:edge, :branch] and
              (is_binary(condition) or (is_atom(condition) and not is_nil(condition))) do
    {branch, nodes} = branch_from_ast(edge_ast, to_string(condition), [], env, meta)
    {branch_declaration_steps(nodes, branch), env}
  end

  defp statement_steps({verb, meta, [edge_ast, opts]}, env)
       when verb in [:edge, :branch] and is_list(opts) do
    condition = condition_from_opts(opts, meta)
    {branch, nodes} = branch_from_ast(edge_ast, condition, opts, env, meta)
    {branch_declaration_steps(nodes, branch), env}
  end

  defp statement_steps({verb, meta, [_edge_ast]}, _env) when verb in [:edge, :branch] do
    raise ArgumentError,
          "decision-tree branches require a condition; use `edge parent ~> child, \"yes\"` or `parent ~> child |> when_(\"yes\")`#{line_suffix(meta)}"
  end

  defp statement_steps({:|>, _meta, _args} = ast, env) do
    {branch, nodes} = branch_from_piped_ast(ast, env)
    {branch_declaration_steps(nodes, branch), env}
  end

  defp statement_steps({:~>, meta, _args}, _env) do
    raise ArgumentError,
          "decision-tree branches require a condition; use `edge parent ~> child, \"yes\"` or `parent ~> child |> when_(\"yes\")`#{line_suffix(meta)}"
  end

  defp statement_steps({name, meta, args} = ast, env) when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(ast, nil, meta)
      {[{:node, node}], Map.put(env, node.id, node.id)}
    else
      unsupported_statement!(ast, meta)
    end
  end

  defp statement_steps(other, _env), do: unsupported_statement!(other, nil)

  defp branch_declaration_steps(nodes, branch) do
    nodes
    |> Enum.reduce([{:branch, branch}], fn node, steps -> [{:node, node} | steps] end)
    |> Enum.reverse()
  end

  defp branch_from_piped_ast(ast, env) do
    {base, modifiers} = unwrap_pipe(ast, [])

    {condition, opts} =
      Enum.reduce(modifiers, {nil, []}, &condition_modifier/2)

    condition = require_condition!(condition, line_meta(base))
    branch_from_ast(base, condition, opts, env, line_meta(base))
  end

  defp condition_modifier({name, _meta, [value]}, {_cond, opts})
       when name in [:when_, :condition, :on, :label, :branch, :edge] and
              (is_binary(value) or is_atom(value)) do
    {to_string(value), opts}
  end

  defp condition_modifier({name, meta, [opts]}, {_cond, prev_opts})
       when name in [:when_, :condition, :on, :label, :branch, :edge] and is_list(opts) do
    {condition_from_opts(opts, meta), Keyword.merge(prev_opts, opts)}
  end

  defp condition_modifier({name, _meta, [value, opts]}, {_cond, prev_opts})
       when name in [:when_, :condition, :on, :label, :branch, :edge] and
              (is_binary(value) or is_atom(value)) and is_list(opts) do
    cond_val = Keyword.get(opts, :condition, to_string(value))
    {cond_val, Keyword.merge(prev_opts, opts)}
  end

  defp condition_modifier(other, _acc) do
    raise ArgumentError,
          "unsupported decision-tree branch modifier: #{Macro.to_string(other)}; " <>
            "use `when_(value)`, `condition(value)`, `on(value)`, `label(value)`, or `branch(value)`"
  end

  defp branch_from_ast({:~>, meta, [from_ast, to_ast]}, condition, opts, env, _statement_meta) do
    {from, from_node} = endpoint_id(from_ast, env, meta)
    {to, to_node} = endpoint_id(to_ast, env, meta)
    nodes = [from_node, to_node] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)
    {%{from: from, to: to, condition: condition, opts: opts}, nodes}
  end

  defp branch_from_ast(other, _condition, _opts, _env, meta) do
    raise ArgumentError,
          "expected `parent ~> child` in decision-tree DSL, got #{Macro.to_string(other)}" <>
            line_suffix(meta)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env, var) do
      {:ok, id} ->
        {id, nil}

      :error ->
        raise ArgumentError, "unknown decision-tree node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, _env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, meta)
      {node.id, node}
    else
      raise ArgumentError, "unknown decision-tree node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported decision-tree branch endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `eligible = decision(\"Eligible?\")`"
  end

  defp node_from_constructor({name, meta, args}, var, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError,
              "unknown decision-tree node constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    {id, opts} = node_id_and_opts(var, positional, opts, meta)
    opts = maybe_put_feature(builder, opts)
    %{id: id, builder: builder, opts: opts}
  end

  defp node_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "decision-tree node constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline decision-tree node constructors need a label/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp maybe_put_feature(:add_outcome, opts), do: opts

  defp maybe_put_feature(_builder, opts) do
    Keyword.put_new(opts, :feature, Keyword.get(opts, :label, ""))
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
          "inline decision-tree node label/id must be a string or atom, got #{inspect(other)}"
  end

  defp condition_from_opts(opts, meta) do
    opts
    |> Keyword.get(
      :condition,
      Keyword.get(
        opts,
        :label,
        Keyword.get(opts, :with, Keyword.get(opts, :when, Keyword.get(opts, :when_)))
      )
    )
    |> require_condition!(meta)
  end

  defp require_condition!(condition, _meta) when is_binary(condition), do: condition

  defp require_condition!(condition, _meta) when is_atom(condition) and not is_nil(condition),
    do: to_string(condition)

  defp require_condition!(condition, _meta) when is_number(condition), do: to_string(condition)

  defp require_condition!(_condition, meta) do
    raise ArgumentError,
          "decision-tree branches require a string condition#{line_suffix(meta)}"
  end

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.DecisionTree, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:branch, %{from: from, to: to, condition: condition} = branch}, acc) do
    opts = Map.get(branch, :opts, [])

    if opts == [] do
      quote do
        Choreo.DecisionTree.branch(
          unquote(acc),
          unquote(Macro.escape(from)),
          unquote(Macro.escape(to)),
          unquote(condition)
        )
      end
    else
      quote do
        Choreo.DecisionTree.branch(
          unquote(acc),
          unquote(Macro.escape(from)),
          unquote(Macro.escape(to)),
          unquote(condition),
          unquote(Macro.escape(opts))
        )
      end
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in decision-tree DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
  end

  # Autocomplete helper stubs
  for verb <- [
        :branch,
        :condition,
        :decision,
        :edge,
        :label,
        :leaf,
        :on,
        :outcome,
        :question,
        :result,
        :root,
        :when_
      ] do
    def unquote(verb)(_arg1 \\ nil, _arg2 \\ nil, _opts \\ []) do
      raise "DSL constructor `#{unquote(verb)}` must be called inside a DSL block"
    end
  end
end
