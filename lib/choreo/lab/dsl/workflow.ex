defmodule Choreo.Lab.DSL.Workflow do
  @moduledoc """
  Experimental Livebook-friendly DSL for sketching workflows.

  This Lab DSL compiles to the stable, pipe-first `Choreo.Workflow` builders and
  returns an ordinary `%Choreo.Workflow{}`. It is useful for business processes,
  approvals, Sagas, CI/CD flows, and system-design walkthroughs where the shape of
  execution matters more than builder ceremony.

  ## Examples

      iex> import Choreo.Lab.DSL.Workflow
      ...> flow = workflow do
      ...>   backend = swimlane("Backend")
      ...>   start = begin("Request received")
      ...>   validate = task("Validate token", swimlane: backend, timeout_ms: 100)
      ...>   authorized = decision("Authorized?")
      ...>   accepted = finish("Return 200")
      ...>   rejected = finish("Return 403")
      ...>
      ...>   start ~> validate
      ...>   validate ~> authorized
      ...>   authorized ~> accepted |> condition("yes")
      ...>   failure authorized ~> rejected, "no"
      ...> end
      iex> Enum.sort(Choreo.Workflow.starts(flow))
      [:start]
      iex> Enum.sort(Choreo.Workflow.ends(flow))
      [:accepted, :rejected]

  Edges can use generic, typed, or pipe-modified forms:

      start ~> validate
      decision ~> approved |> condition("yes")
      edge task ~> retry_step, retry: "temporary failure"
      failure task ~> rollback, "validation failed"
      compensation rollback ~> done, "cleanup finished"
  """

  @type node_decl :: %{id: Yog.node_id(), builder: atom(), opts: keyword()}
  @type swimlane_decl :: %{id: String.t(), opts: keyword()}
  @type edge_decl :: %{from: Yog.node_id(), to: Yog.node_id(), opts: keyword()}

  @node_verbs [
    :begin,
    :start,
    :task,
    :step,
    :decision,
    :gateway,
    :fork,
    :split,
    :join,
    :merge,
    :compensation,
    :rollback,
    :event,
    :timer,
    :signal,
    :finish,
    :done,
    :end_event,
    :terminal
  ]

  @node_builders %{
    begin: :add_start,
    start: :add_start,
    task: :add_task,
    step: :add_task,
    decision: :add_decision,
    gateway: :add_decision,
    fork: :add_fork,
    split: :add_fork,
    join: :add_join,
    merge: :add_join,
    compensation: :add_compensation,
    rollback: :add_compensation,
    event: :add_event,
    timer: :add_event,
    signal: :add_event,
    finish: :add_end,
    done: :add_end,
    end_event: :add_end,
    terminal: :add_end
  }

  @swimlane_verbs [:swimlane, :lane]
  @edge_verbs [:sequence, :then, :compensation, :compensates, :retry, :failure, :timeout, :error]

  @edge_type_aliases %{
    sequence: :sequence,
    then: :sequence,
    compensation: :compensation,
    compensates: :compensation,
    retry: :retry,
    failure: :failure,
    timeout: :timeout,
    error: :error
  }

  @doc """
  Returns the vocabulary supported by the workflow DSL.

      iex> taxonomy = Choreo.Lab.DSL.Workflow.taxonomy()
      iex> :task in taxonomy.nodes
      true
      iex> :swimlane in taxonomy.swimlanes
      true
      iex> :failure in taxonomy.edges
      true
  """
  @spec taxonomy() :: %{
          swimlanes: [atom()],
          nodes: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def taxonomy do
    %{
      swimlanes: @swimlane_verbs,
      nodes: @node_verbs,
      edges: [:~>, :edge | @edge_verbs],
      modifiers: [:on, :label, :condition, :when_, :weight | @edge_verbs],
      options: [
        :label,
        :with,
        :id,
        :description,
        :swimlane,
        :timeout_ms,
        :retry,
        :retry_backoff_ms,
        :handler,
        :for,
        :condition,
        :edge_type,
        :weight | @edge_verbs
      ]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: map()
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.Workflow{}` from a compact Lab DSL block.
  """
  defmacro workflow(do: block), do: compile(block)
  defmacro workflow(opts, do: block), do: compile(block, opts)

  defp compile(block, opts \\ []) do
    {steps, _env} =
      block
      |> statements()
      |> Enum.reduce({[], empty_env()}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {steps ++ statement_steps, env}
      end)

    Enum.reduce(steps, quote(do: Choreo.Workflow.new(unquote(Macro.escape(opts)))), &pipe_step/2)
  end

  defp statements({:__block__, _meta, list}), do: list
  defp statements(nil), do: []
  defp statements(single), do: [single]

  defp empty_env, do: %{nodes: %{}, swimlanes: %{}}

  defp statement_steps({:=, meta, [{var, _, context}, constructor]}, env)
       when is_atom(var) and is_atom(context) do
    cond do
      swimlane_constructor?(constructor) ->
        swimlane = swimlane_from_constructor(constructor, var, meta)
        {[{:swimlane, swimlane}], put_in(env.swimlanes[var], swimlane.id)}

      node_constructor?(constructor) ->
        node = node_from_constructor(constructor, var, env, meta)
        {[{:node, node}], put_in(env.nodes[var], node.id)}

      true ->
        raise ArgumentError,
              "expected workflow constructor, got #{Macro.to_string(constructor)}#{line_suffix(meta)}"
    end
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

  defp statement_steps({:|>, _meta, _args} = ast, env) do
    {edge, nodes} = edge_from_piped_ast(ast, env)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({:~>, meta, _args} = ast, env) do
    {edge, nodes} = edge_from_ast(ast, [], env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({name, meta, args} = ast, env) when is_atom(name) and is_list(args) do
    cond do
      name in @edge_verbs ->
        typed_edge_statement(name, typed_edge_args!(name, args, meta), env, meta)

      name in @swimlane_verbs ->
        swimlane = swimlane_from_constructor(ast, nil, meta)
        {[{:swimlane, swimlane}], env}

      Map.has_key?(@node_builders, name) ->
        node = node_from_constructor(ast, nil, env, meta)
        {[{:node, node}], env}

      true ->
        unsupported_statement!(ast, meta)
    end
  end

  defp statement_steps(other, _env), do: unsupported_statement!(other, nil)

  defp typed_edge_args!(_name, [edge_ast, label, opts], _meta)
       when is_binary(label) and is_list(opts),
       do: {edge_ast, [label: label] ++ opts}

  defp typed_edge_args!(_name, [edge_ast, label], _meta) when is_binary(label),
    do: {edge_ast, [label: label]}

  defp typed_edge_args!(_name, [edge_ast, opts], _meta) when is_list(opts),
    do: {edge_ast, opts}

  defp typed_edge_args!(_name, [edge_ast], _meta), do: {edge_ast, []}

  defp typed_edge_args!(name, args, meta) do
    raise ArgumentError,
          "unsupported workflow edge form `#{name}/#{length(args)}`#{line_suffix(meta)}; " <>
            "use `#{name} from ~> to`, `#{name} from ~> to, label`, or `#{name} from ~> to, opts`"
  end

  defp typed_edge_statement(name, {edge_ast, opts}, env, meta) do
    opts = opts |> normalize_edge_opts() |> edge_type_opts(name)
    {edge, nodes} = edge_from_ast(edge_ast, opts, env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

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

  defp unwrap_pipe({:|>, _meta, [left, right]}, acc), do: unwrap_pipe(left, [right | acc])
  defp unwrap_pipe(base, acc), do: {base, acc}

  defp modifier_opt({name, _meta, [value]}, acc) when name in [:on, :label] do
    Keyword.put(acc, :label, value)
  end

  defp modifier_opt({name, _meta, [value]}, acc) when name in [:condition, :when_] do
    Keyword.put(acc, :condition, value)
  end

  defp modifier_opt({:weight, _meta, [value]}, acc), do: Keyword.put(acc, :weight, value)

  defp modifier_opt({name, _meta, []}, acc) when name in @edge_verbs do
    edge_type_opts(acc, name)
  end

  defp modifier_opt({name, _meta, [value]}, acc) when name in @edge_verbs do
    acc
    |> edge_type_opts(name)
    |> Keyword.put_new(:label, value)
  end

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported workflow edge modifier: #{Macro.to_string(other)}; " <>
            "use `on(value)`, `condition(value)`, `retry(value)`, `failure(value)`, or `weight(value)`"
  end

  defp edge_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, from_node} = endpoint_id(from_ast, env, meta)
    {to, to_node} = endpoint_id(to_ast, env, meta)
    nodes = [from_node, to_node] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)
    {%{from: from, to: to, opts: normalize_edge_opts(opts)}, nodes}
  end

  defp edge_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in workflow DSL, got #{Macro.to_string(other)}" <>
            line_suffix(meta)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env.nodes, var) do
      {:ok, id} -> {id, nil}
      :error -> raise ArgumentError, "unknown workflow node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, env, meta)
      {node.id, node}
    else
      raise ArgumentError, "unknown workflow node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported workflow edge endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `validate = task(\"Validate\")`"
  end

  defp node_from_constructor({name, meta, args}, var, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError, "unknown workflow node constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)

    opts =
      opts
      |> resolve_swimlane_option(:swimlane, env, meta)
      |> resolve_node_option(:for, env, meta)

    {id, opts} = node_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
  end

  defp swimlane_from_constructor({name, meta, args}, var, _statement_meta)
       when name in @swimlane_verbs and is_list(args) do
    {opts, positional} = pop_trailing_opts(args)
    {id, opts} = swimlane_id_and_opts(var, positional, opts, meta)
    %{id: id, opts: opts}
  end

  defp pop_trailing_opts(args) do
    case List.last(args) do
      last when is_list(last) ->
        if Keyword.keyword?(last), do: {last, Enum.drop(args, -1)}, else: {[], args}

      _other ->
        {[], args}
    end
  end

  defp node_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "workflow node constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline workflow node constructors need a label/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp swimlane_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "workflow swimlane constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {to_string(explicit_id), maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {to_string(var), maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {swimlane_id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline workflow swimlane constructors need a label/id or `id:` option#{line_suffix(meta)}"
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
          "inline workflow node label/id must be a string or atom, got #{inspect(other)}"
  end

  defp swimlane_id_from_label(id) when is_atom(id), do: to_string(id)
  defp swimlane_id_from_label(id) when is_binary(id), do: id |> slug_atom() |> to_string()

  defp swimlane_id_from_label(other) do
    raise ArgumentError,
          "inline workflow swimlane label/id must be a string or atom, got #{inspect(other)}"
  end

  defp slug_atom(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> raise ArgumentError, "cannot derive a workflow node id from an empty label"
      slug -> String.to_atom(slug)
    end
  end

  defp resolve_swimlane_option(opts, key, env, meta) do
    Keyword.update(opts, key, nil, &resolve_swimlane_reference(&1, env, key, meta))
    |> Keyword.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp resolve_swimlane_reference({var, _meta, context}, env, key, meta)
       when is_atom(var) and is_atom(context) do
    case Map.fetch(env.swimlanes, var) do
      {:ok, id} ->
        id

      :error ->
        raise ArgumentError,
              "unknown workflow swimlane variable `#{var}` in `#{key}:`#{line_suffix(meta)}"
    end
  end

  defp resolve_swimlane_reference(value, _env, _key, _meta), do: value

  defp resolve_node_option(opts, key, env, meta) do
    Keyword.update(opts, key, nil, &resolve_node_reference(&1, env, key, meta))
    |> Keyword.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp resolve_node_reference({var, _meta, context}, env, key, meta)
       when is_atom(var) and is_atom(context) do
    case Map.fetch(env.nodes, var) do
      {:ok, id} ->
        id

      :error ->
        raise ArgumentError,
              "unknown workflow node variable `#{var}` in `#{key}:`#{line_suffix(meta)}"
    end
  end

  defp resolve_node_reference(value, _env, _key, _meta), do: value

  defp normalize_edge_opts(opts) do
    opts
    |> normalize_label_alias(:with)
    |> normalize_condition_alias(:when_)
    |> normalize_edge_aliases()
  end

  defp normalize_label_alias(opts, key) do
    {value, opts} = Keyword.pop(opts, key)
    if value == nil, do: opts, else: Keyword.put_new(opts, :label, value)
  end

  defp normalize_condition_alias(opts, key) do
    {value, opts} = Keyword.pop(opts, key)
    if value == nil, do: opts, else: Keyword.put_new(opts, :condition, value)
  end

  defp normalize_edge_aliases(opts) do
    Enum.reduce(@edge_verbs, opts, fn key, acc ->
      {value, acc} = Keyword.pop(acc, key)

      if value == nil do
        acc
      else
        acc |> edge_type_opts(key) |> Keyword.put_new(:label, value)
      end
    end)
  end

  defp edge_type_opts(opts, name) do
    Keyword.put(opts, :edge_type, Map.fetch!(@edge_type_aliases, name))
  end

  defp swimlane_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: name in @swimlane_verbs

  defp swimlane_constructor?(_other), do: false

  defp node_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(@node_builders, name)

  defp node_constructor?(_other), do: false

  defp pipe_step({:swimlane, %{id: id, opts: opts}}, acc) do
    quote do
      Choreo.Workflow.add_swimlane(
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.Workflow, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, opts: opts}}, acc) do
    quote do
      Choreo.Workflow.connect(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in workflow DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
  end

  defp line_meta({_name, meta, _args}) when is_list(meta), do: meta
  defp line_meta(_other), do: []

  defp line_suffix(meta) when is_list(meta) do
    case Keyword.get(meta, :line) do
      nil -> ""
      line -> " (line #{line})"
    end
  end

  defp line_suffix(_meta), do: ""
end
