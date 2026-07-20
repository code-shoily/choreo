defmodule Choreo.Lab.DSL.Domain do
  @moduledoc """
  Experimental Livebook-friendly DSL for sketching DDD domain models.

  This Lab DSL compiles to the stable, pipe-first `Choreo.Domain` builders and
  returns an ordinary `%Choreo.Domain{}`. It supports strategic context maps,
  tactical event-storming flows, Wlaschin-style workflow/type sketches, and named
  scenarios for Event Modeling projections.

  ## Examples

      iex> import Choreo.Lab.DSL.Domain
      ...> model = domain do
      ...>   checkout = context_boundary("Checkout")
      ...>   customer = actor("Customer")
      ...>   place_order = command("Place Order", cluster: checkout)
      ...>   order = aggregate("Order", cluster: checkout, invariants: ["Cannot place an empty order."])
      ...>   placed = event("Order Placed", cluster: checkout)
      ...>   summary = read_model("Order Summary", cluster: checkout)
      ...>
      ...>   customer ~> place_order |> initiates("starts")
      ...>   place_order ~> order |> handles("validates")
      ...>   order ~> placed |> emits("records")
      ...>   placed ~> summary |> projects_to("updates")
      ...> end
      iex> Choreo.Domain.nodes(model).order.type
      :aggregate

  Strategic context maps can use context nodes and context-mapping relationships:

      ordering = context("Ordering", subdomain: :core)
      billing = context("Billing", subdomain: :supporting)
      customer_supplier ordering ~> billing, "Invoice requests"

  Tactical edges can use generic, typed, or pipe-modified forms:

      actor ~> command |> initiates("submits")
      command ~> aggregate |> handles("validates")
      aggregate ~> event |> emits("records")
      event ~> policy |> triggers("reacts")
      event ~> read_model |> projects_to("updates")
      edge upstream ~> downstream, translates_via: "ACL"
  """

  @type node_decl :: %{id: Yog.node_id(), builder: atom(), opts: keyword()}
  @type cluster_decl :: %{id: String.t(), builder: atom(), opts: keyword()}
  @type edge_decl :: %{from: Yog.node_id(), to: Yog.node_id(), opts: keyword(), builder: atom()}
  @type scenario_decl :: %{name: atom(), opts: keyword()}

  @node_verbs [
    :context,
    :bounded_context,
    :actor,
    :user,
    :command,
    :aggregate,
    :entity,
    :event,
    :domain_event,
    :read_model,
    :projection,
    :policy,
    :saga,
    :external_system,
    :external,
    :type,
    :data_type,
    :workflow,
    :process,
    :acl,
    :anti_corruption_layer
  ]

  @node_builders %{
    context: :add_context,
    bounded_context: :add_context,
    actor: :add_actor,
    user: :add_actor,
    command: :add_command,
    aggregate: :add_aggregate,
    entity: :add_aggregate,
    event: :add_event,
    domain_event: :add_event,
    read_model: :add_read_model,
    projection: :add_read_model,
    policy: :add_policy,
    saga: :add_policy,
    external_system: :add_external_system,
    external: :add_external_system,
    type: :add_type,
    data_type: :add_type,
    workflow: :add_workflow,
    process: :add_workflow,
    acl: :add_acl,
    anti_corruption_layer: :add_acl
  }

  @cluster_verbs [:context_boundary, :boundary, :context_cluster]
  @domain_edge_verbs [
    :initiates,
    :handles,
    :emits,
    :triggers,
    :projects_to,
    :notifies,
    :translates_via
  ]

  @context_edge_verbs [
    :shared_kernel,
    :customer_supplier,
    :conformist,
    :open_host_service,
    :published_language,
    :anti_corruption
  ]

  @edge_verbs [
    :initiates,
    :handles,
    :emits,
    :triggers,
    :projects_to,
    :notifies,
    :translates_via,
    :connects,
    :shared_kernel,
    :customer_supplier,
    :conformist,
    :open_host_service,
    :published_language,
    :anti_corruption
  ]

  @context_relationships %{
    shared_kernel: :shared_kernel,
    customer_supplier: :customer_supplier,
    conformist: :conformist,
    open_host_service: :open_host_service,
    published_language: :published_language,
    anti_corruption: :acl
  }

  @doc """
  Returns the vocabulary supported by the domain DSL.

      iex> taxonomy = Choreo.Lab.DSL.Domain.taxonomy()
      iex> :aggregate in taxonomy.nodes
      true
      iex> :context_boundary in taxonomy.clusters
      true
      iex> :emits in taxonomy.edges
      true
  """
  @spec taxonomy() :: %{
          clusters: [atom()],
          nodes: [atom()],
          edges: [atom()],
          events: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def taxonomy do
    %{
      clusters: @cluster_verbs,
      nodes: @node_verbs,
      edges: [:~>, :edge | @edge_verbs],
      events: [:scenario],
      modifiers: [:on, :label | @edge_verbs],
      options: [
        :label,
        :with,
        :id,
        :description,
        :cluster,
        :parent,
        :fields,
        :subdomain,
        :owner,
        :invariants,
        :path | @edge_verbs
      ]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: map()
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.Domain{}` from a compact Lab DSL block.
  """
  defmacro domain(do: block), do: compile(block)
  defmacro domain(opts, do: block), do: compile(block, opts)

  defp compile(block, opts \\ []) do
    {steps, _env} =
      block
      |> statements()
      |> Enum.reduce({[], empty_env()}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {steps ++ statement_steps, env}
      end)

    Enum.reduce(steps, quote(do: Choreo.Domain.new(unquote(Macro.escape(opts)))), &pipe_step/2)
  end

  defp statements({:__block__, _meta, list}), do: list
  defp statements(nil), do: []
  defp statements(single), do: [single]

  defp empty_env, do: %{nodes: %{}, clusters: %{}}

  defp statement_steps({:=, meta, [{var, _, context}, constructor]}, env)
       when is_atom(var) and is_atom(context) do
    cond do
      cluster_constructor?(constructor) ->
        cluster = cluster_from_constructor(constructor, var, env, meta)
        {[{:cluster, cluster}], put_in(env.clusters[var], cluster.id)}

      node_constructor?(constructor) ->
        node = node_from_constructor(constructor, var, env, meta)
        {[{:node, node}], put_in(env.nodes[var], node.id)}

      true ->
        raise ArgumentError,
              "expected domain constructor, got #{Macro.to_string(constructor)}#{line_suffix(meta)}"
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

  defp statement_steps({:scenario, meta, [name, opts]}, env)
       when is_atom(name) and is_list(opts) do
    scenario = scenario_from_opts(name, opts, env, meta)
    {[{:scenario, scenario}], env}
  end

  defp statement_steps({:scenario, meta, [name, label, opts]}, env)
       when is_atom(name) and is_binary(label) and is_list(opts) do
    scenario = scenario_from_opts(name, Keyword.put_new(opts, :label, label), env, meta)
    {[{:scenario, scenario}], env}
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

      name in @cluster_verbs ->
        cluster = cluster_from_constructor(ast, nil, env, meta)
        {[{:cluster, cluster}], env}

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
          "unsupported domain edge form `#{name}/#{length(args)}`#{line_suffix(meta)}; " <>
            "use `#{name} from ~> to`, `#{name} from ~> to, label`, or `#{name} from ~> to, opts`"
  end

  defp typed_edge_statement(name, {edge_ast, opts}, env, meta) do
    opts = opts |> normalize_edge_opts() |> edge_type_opts(name)
    {edge, nodes} = edge_from_ast(edge_ast, opts, env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp edge_declaration_steps(nodes, edge) do
    nodes
    |> Enum.reverse()
    |> Enum.reduce([{:edge, edge}], fn node, steps -> [{:node, node} | steps] end)
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
          "unsupported domain edge modifier: #{Macro.to_string(other)}; " <>
            "use `initiates(value)`, `handles(value)`, `emits(value)`, `triggers(value)`, or `projects_to(value)`"
  end

  defp edge_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, to, declared_nodes} = domain_endpoints(from_ast, to_ast, env, meta)
    {%{from: from, to: to, opts: normalize_edge_opts(opts)}, declared_nodes}
  end

  defp edge_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in domain DSL, got #{Macro.to_string(other)}" <>
            line_suffix(meta)
  end

  defp domain_endpoints(from_ast, to_ast, env, meta) do
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
    case Map.fetch(env.nodes, var) do
      {:ok, id} -> {id, nil}
      :error -> raise ArgumentError, "unknown domain node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, env, meta)
      {node.id, node}
    else
      raise ArgumentError, "unknown domain node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported domain edge endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `order = aggregate(\"Order\")`"
  end

  defp node_from_constructor({name, meta, args}, var, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError, "unknown domain node constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    opts = resolve_cluster_option(opts, :cluster, env, meta)
    {id, opts} = node_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
  end

  defp cluster_from_constructor({name, meta, args}, var, env, _statement_meta)
       when name in @cluster_verbs and is_list(args) do
    {opts, positional} = pop_trailing_opts(args)
    opts = resolve_cluster_option(opts, :parent, env, meta)
    {id, opts} = cluster_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: :add_context_boundary, opts: opts}
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
              "domain node constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline domain node constructors need a label/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp cluster_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "domain cluster constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {to_string(explicit_id), maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {to_string(var), maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {cluster_id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline domain cluster constructors need a label/id or `id:` option#{line_suffix(meta)}"
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
          "inline domain node label/id must be a string or atom, got #{inspect(other)}"
  end

  defp cluster_id_from_label(id) when is_atom(id), do: to_string(id)
  defp cluster_id_from_label(id) when is_binary(id), do: id |> slug_atom() |> to_string()

  defp cluster_id_from_label(other) do
    raise ArgumentError,
          "inline domain cluster label/id must be a string or atom, got #{inspect(other)}"
  end

  defp slug_atom(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> raise ArgumentError, "cannot derive a domain node id from an empty label"
      slug -> String.to_atom(slug)
    end
  end

  defp resolve_cluster_option(opts, key, env, meta) do
    Keyword.update(opts, key, nil, &resolve_cluster_reference(&1, env, key, meta))
    |> Keyword.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp resolve_cluster_reference({var, _meta, context}, env, key, meta)
       when is_atom(var) and is_atom(context) do
    case Map.fetch(env.clusters, var) do
      {:ok, id} ->
        id

      :error ->
        raise ArgumentError,
              "unknown domain cluster variable `#{var}` in `#{key}:`#{line_suffix(meta)}"
    end
  end

  defp resolve_cluster_reference(value, _env, _key, _meta), do: value

  defp scenario_from_opts(name, opts, env, meta) do
    path =
      opts
      |> Keyword.fetch!(:path)
      |> Enum.map(&resolve_node_reference(&1, env, :path, meta))

    %{name: name, opts: Keyword.put(opts, :path, path)}
  end

  defp resolve_node_reference({var, _meta, context}, env, key, meta)
       when is_atom(var) and is_atom(context) do
    case Map.fetch(env.nodes, var) do
      {:ok, id} ->
        id

      :error ->
        raise ArgumentError,
              "unknown domain node variable `#{var}` in `#{key}:`#{line_suffix(meta)}"
    end
  end

  defp resolve_node_reference(value, _env, _key, _meta), do: value

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

  defp edge_type_opts(opts, name) when name in @domain_edge_verbs do
    opts
    |> Keyword.put(:builder, name)
    |> Keyword.put(:type, :domain_relationship)
    |> Keyword.put(:relationship, name)
  end

  defp edge_type_opts(opts, name) when name in @context_edge_verbs do
    opts
    |> Keyword.put(:builder, :connect_contexts)
    |> Keyword.put(:relationship, Map.fetch!(@context_relationships, name))
  end

  defp edge_type_opts(opts, :connects), do: Keyword.put(opts, :builder, :connect)

  defp cluster_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: name in @cluster_verbs

  defp cluster_constructor?(_other), do: false

  defp node_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(@node_builders, name)

  defp node_constructor?(_other), do: false

  defp pipe_step({:cluster, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.Domain, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.Domain, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, opts: opts}}, acc) do
    builder = Keyword.get(opts, :builder, :connect)
    opts = Keyword.delete(opts, :builder)

    quote do
      apply(Choreo.Domain, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:scenario, %{name: name, opts: opts}}, acc) do
    quote do
      Choreo.Domain.add_scenario(
        unquote(acc),
        unquote(Macro.escape(name)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in domain DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
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
