defmodule Choreo.Lab.DSL.Requirement do
  @moduledoc """
  Experimental Livebook-friendly DSL for sketching requirements traceability models.

  This Lab DSL compiles to the stable, pipe-first `Choreo.Requirement` builders and
  returns an ordinary `%Choreo.Requirement{}`. It is useful for quickly connecting
  requirements to stakeholders, implementation components, tests, and traceability
  links in design notebooks.

  ## Examples

      iex> import Choreo.Lab.DSL.Requirement
      ...> model = requirements "Auth v2" do
      ...>   security = stakeholder("Security Team")
      ...>   mfa = functional("Users must authenticate with MFA", id: "REQ-001", risk: :high)
      ...>   auth = component("Auth Service")
      ...>   mfa_test = test_case("MFA login test")
      ...>
      ...>   security ~> mfa |> traces("owns")
      ...>   auth ~> mfa |> satisfies("implements")
      ...>   mfa_test ~> mfa |> verifies("proves")
      ...> end
      iex> model.name
      "Auth v2"
      iex> Enum.sort(Choreo.Requirement.requirements(model))
      [:mfa]

  Requirement constructors accept a text/label and can infer stable options for
  quick sketches:

      mfa = requirement("Users must authenticate with MFA", id: "REQ-001")
      perf = performance("p95 latency below 100ms", risk: :high)

  Edges can use generic, typed, or pipe-modified forms:

      auth ~> mfa |> satisfies("implements")
      test ~> mfa |> verifies("covers")
      child ~> parent |> refines("elaborates")
      edge req_a ~> req_b, depends: "requires first"
      contains parent ~> child, "breaks down"
  """

  @type node_decl :: %{id: Yog.node_id(), builder: atom(), opts: keyword()}
  @type edge_decl :: %{from: Yog.node_id(), to: Yog.node_id(), opts: keyword(), builder: atom()}

  @requirement_verbs [
    :requirement,
    :req,
    :functional,
    :interface_requirement,
    :performance,
    :physical,
    :constraint,
    :design_constraint
  ]

  @other_node_verbs [
    :component,
    :service,
    :module,
    :system,
    :test_case,
    :test,
    :verification,
    :stakeholder,
    :owner,
    :team,
    :actor
  ]

  @node_verbs @requirement_verbs ++ @other_node_verbs

  @node_builders %{
    requirement: :add_requirement,
    req: :add_requirement,
    functional: :add_requirement,
    interface_requirement: :add_requirement,
    performance: :add_requirement,
    physical: :add_requirement,
    constraint: :add_requirement,
    design_constraint: :add_requirement,
    component: :add_component,
    service: :add_component,
    module: :add_component,
    system: :add_component,
    test_case: :add_test,
    test: :add_test,
    verification: :add_test,
    stakeholder: :add_stakeholder,
    owner: :add_stakeholder,
    team: :add_stakeholder,
    actor: :add_stakeholder
  }

  @requirement_kinds %{
    requirement: :requirement,
    req: :requirement,
    functional: :functional,
    interface_requirement: :interface,
    performance: :performance,
    physical: :physical,
    constraint: :design_constraint,
    design_constraint: :design_constraint
  }

  @edge_verbs [:satisfies, :verifies, :refines, :depends, :traces, :contains, :derives, :relates]

  @edge_builders %{
    satisfies: :satisfies,
    verifies: :verifies,
    refines: :refines,
    depends: :depends,
    traces: :traces,
    contains: :contains,
    derives: :derives,
    relates: :relate
  }

  @doc """
  Returns the vocabulary supported by the requirement DSL.

      iex> taxonomy = Choreo.Lab.DSL.Requirement.taxonomy()
      iex> :functional in taxonomy.requirements
      true
      iex> :component in taxonomy.nodes
      true
      iex> :satisfies in taxonomy.edges
      true
  """
  @spec taxonomy() :: %{
          requirements: [atom()],
          nodes: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def taxonomy do
    %{
      requirements: @requirement_verbs,
      nodes: @node_verbs,
      edges: [:~>, :edge | @edge_verbs],
      modifiers: [:on, :label | @edge_verbs],
      options: [
        :label,
        :with,
        :id,
        :text,
        :risk,
        :verification,
        :kind,
        :type,
        :docref | @edge_verbs
      ]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: map()
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.Requirement{}` from a compact Lab DSL block.
  """
  defmacro requirements(do: block), do: compile(block)
  defmacro requirements(name_or_opts, do: block), do: compile(block, name_or_opts)

  defp compile(block, name_or_opts \\ []) do
    {steps, _env} =
      block
      |> statements()
      |> Enum.reduce({[], %{}}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {steps ++ statement_steps, env}
      end)

    Enum.reduce(
      steps,
      quote(do: Choreo.Requirement.new(unquote(Macro.escape(name_or_opts)))),
      &pipe_step/2
    )
  end

  defp statements({:__block__, _meta, list}), do: list
  defp statements(nil), do: []
  defp statements(single), do: [single]

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

      Map.has_key?(@node_builders, name) ->
        node = node_from_constructor(ast, nil, meta)
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
          "unsupported requirement edge form `#{name}/#{length(args)}`#{line_suffix(meta)}; " <>
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
          "unsupported requirement edge modifier: #{Macro.to_string(other)}; " <>
            "use `satisfies(value)`, `verifies(value)`, `refines(value)`, or `traces(value)`"
  end

  defp edge_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, to, declared_nodes} = requirement_endpoints(from_ast, to_ast, env, meta)
    {%{from: from, to: to, opts: normalize_edge_opts(opts)}, declared_nodes}
  end

  defp edge_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in requirement DSL, got #{Macro.to_string(other)}" <>
            line_suffix(meta)
  end

  defp requirement_endpoints(from_ast, to_ast, env, meta) do
    {from, from_node} = endpoint_id(from_ast, env, meta)
    {to, to_node} = endpoint_id(to_ast, env, meta)
    {from, to, declared_endpoint_nodes(from_node, to_node)}
  end

  defp declared_endpoint_nodes(from_node, to_node) do
    [from_node, to_node]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env, var) do
      {:ok, id} ->
        {id, nil}

      :error ->
        raise ArgumentError, "unknown requirement node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, _env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, meta)
      {node.id, node}
    else
      raise ArgumentError, "unknown requirement node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported requirement edge endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `mfa = requirement(\"MFA\")`"
  end

  defp node_from_constructor({name, meta, args}, var, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError, "unknown requirement node constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    {id, opts} = node_id_and_opts(var, positional, opts, meta)
    opts = normalize_node_opts(name, id, positional, opts)
    %{id: id, builder: builder, opts: opts}
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
    {explicit_id, opts} = Keyword.pop(opts, :node_id)
    {explicit_node_id, opts} = Keyword.pop(opts, :node)
    node_id = explicit_node_id || explicit_id

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "requirement node constructors take at most one positional label/text#{line_suffix(meta)}"

      node_id != nil ->
        {node_id, opts}

      var != nil ->
        {var, opts}

      positional != [] ->
        {id_from_label(List.first(positional)), opts}

      true ->
        raise ArgumentError,
              "inline requirement node constructors need text/label, `node:`, or `node_id:`#{line_suffix(meta)}"
    end
  end

  defp normalize_node_opts(name, node_id, positional, opts) when name in @requirement_verbs do
    text = Keyword.get(opts, :text) || text_from_positional(positional) || to_string(node_id)
    human_id = Keyword.get(opts, :id) || human_id_from(node_id, text)

    opts
    |> Keyword.put(:id, human_id)
    |> Keyword.put(:text, text)
    |> Keyword.put_new(:kind, Map.fetch!(@requirement_kinds, name))
  end

  defp normalize_node_opts(_name, node_id, positional, opts) do
    opts
    |> maybe_put_label(text_from_positional(positional) || Keyword.get(opts, :label) || node_id)
  end

  defp text_from_positional([value]) when is_binary(value), do: value
  defp text_from_positional([value]) when is_atom(value), do: to_string(value)
  defp text_from_positional(_other), do: nil

  defp human_id_from(node_id, _text) when is_atom(node_id),
    do: node_id |> to_string() |> String.upcase()

  defp human_id_from(node_id, _text) when is_binary(node_id), do: node_id
  defp human_id_from(_node_id, text), do: text

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
          "inline requirement node text/label must be a string or atom, got #{inspect(other)}"
  end

  defp slug_atom(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> raise ArgumentError, "cannot derive a requirement node id from an empty label"
      slug -> String.to_atom(slug)
    end
  end

  defp normalize_edge_opts(opts) do
    opts
    |> normalize_label_alias(:with)
    |> normalize_edge_aliases()
  end

  defp normalize_label_alias(opts, key) do
    {value, opts} = Keyword.pop(opts, key)
    if value == nil, do: opts, else: Keyword.put_new(opts, :label, value)
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
    type = if name == :relates, do: :traces, else: name
    Keyword.put(opts, :type, type)
  end

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.Requirement, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, opts: opts}}, acc) do
    builder = Map.fetch!(@edge_builders, Keyword.get(opts, :type, :traces))
    opts = Keyword.delete(opts, :type)

    quote do
      apply(Choreo.Requirement, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in requirement DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
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
