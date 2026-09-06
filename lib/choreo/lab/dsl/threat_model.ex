defmodule Choreo.Lab.DSL.ThreatModel do
  import Choreo.Lab.DSL.Compiler

  @moduledoc """
  Experimental Livebook-friendly DSL for sketching STRIDE threat models.

  This Lab DSL compiles to the stable, pipe-first `Choreo.ThreatModel` builders
  and returns an ordinary `%Choreo.ThreatModel{}`. It is intentionally small: use
  it to sketch external entities, processes, data stores, trust boundaries, and
  data flows quickly, then use `Choreo.ThreatModel.Analysis` explicitly for the
  real security review.

  ## Examples

      iex> import Choreo.Lab.DSL.ThreatModel
      ...> model = threat_model do
      ...>   internet = boundary("Internet", level: 0)
      ...>   app = boundary("Application", level: 2)
      ...>   data = boundary("Data", level: 3)
      ...>
      ...>   user = external_entity("User", boundary: internet)
      ...>   api = process("API Gateway", boundary: app, privilege: :user)
      ...>   db = data_store("Tenant DB", boundary: data, sensitivity: :confidential)
      ...>
      ...>   user ~> api |> encrypted("HTTPS request", protocol: :https)
      ...>   api ~> db |> flow("Reads tenant config", protocol: :sql)
      ...> end
      iex> Enum.sort(Choreo.ThreatModel.elements(model))
      [:api, :db, :user]
      iex> Choreo.ThreatModel.boundary_of(model, :api)
      "app"
      iex> edges = Choreo.ThreatModel.edges_with_meta(model)
      iex> Enum.any?(edges, fn {from, to, _, meta} -> from == :api and to == :db and meta.protocol == :sql end)
      true
      iex> Enum.any?(edges, fn {from, to, _, meta} -> from == :user and to == :api and meta.encrypted end)
      true

  Edges can use generic, typed, or pipe-modified forms:

      user ~> api
      user ~> api |> encrypted("HTTPS request", protocol: :https)
      flow api ~> db, "SQL query", protocol: :sql
      unencrypted worker ~> queue, "plain queue message"
  """

  @boundary_verbs [:boundary, :trust_boundary, :zone]

  @node_verbs [
    :external_entity,
    :external,
    :actor,
    :user,
    :client,
    :third_party,
    :process,
    :service,
    :api,
    :worker,
    :function,
    :data_store,
    :store,
    :database,
    :db,
    :cache,
    :queue,
    :bucket
  ]

  @node_builders %{
    external_entity: :add_external_entity,
    external: :add_external_entity,
    actor: :add_external_entity,
    user: :add_external_entity,
    client: :add_external_entity,
    third_party: :add_external_entity,
    process: :add_process,
    service: :add_process,
    api: :add_process,
    worker: :add_process,
    function: :add_process,
    data_store: :add_data_store,
    store: :add_data_store,
    database: :add_data_store,
    db: :add_data_store,
    cache: :add_data_store,
    queue: :add_data_store,
    bucket: :add_data_store
  }

  @edge_verbs [:flow, :data_flow, :sends, :reads, :writes, :encrypted, :unencrypted]

  @doc """
  Returns the vocabulary supported by the threat-model DSL.

      iex> taxonomy = Choreo.Lab.DSL.ThreatModel.taxonomy()
      iex> :boundary in taxonomy.boundaries
      true
      iex> :process in taxonomy.nodes
      true
      iex> :encrypted in taxonomy.modifiers
      true
  """
  @spec taxonomy() :: %{
          boundaries: [atom()],
          nodes: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def taxonomy do
    %{
      boundaries: @boundary_verbs,
      nodes: @node_verbs,
      edges: [:~>, :edge | @edge_verbs],
      modifiers: [:on, :label, :edge, :with, :protocol, :encrypted, :unencrypted | @edge_verbs],
      options: [
        :id,
        :label,
        :with,
        :boundary,
        :level,
        :description,
        :privilege,
        :sensitivity,
        :retention,
        :protocol,
        :encrypted | @edge_verbs
      ]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: map()
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.ThreatModel{}` from a compact Lab DSL block.
  """
  defmacro threat_model(do: block), do: compile(block)
  defmacro threat_model(opts, do: block), do: compile(block, opts)

  defp compile(block, opts \\ []) do
    {steps_reversed, _env} =
      block
      |> statements()
      |> Enum.reduce({[], empty_env()}, fn statement, {steps, env} ->
        {statement_steps, env} = process_statement(statement, env)
        {Enum.reverse(statement_steps, steps), env}
      end)

    Enum.reduce(
      Enum.reverse(steps_reversed),
      quote(do: Choreo.ThreatModel.new(unquote(Macro.escape(opts)))),
      &pipe_step/2
    )
  end

  defp process_statement(statement, env) do
    case extract_do_block(statement) do
      {block, stripped_statement} when not is_nil(block) ->
        compile_nested_boundary(stripped_statement, block, env)

      _ ->
        statement_steps(statement, env)
    end
  end

  defp compile_nested_boundary(statement, block, env) do
    {boundary_steps, inner_env} = statement_steps(statement, env)
    boundary_id = get_boundary_id(boundary_steps)

    {block_steps, block_env} =
      compile_block_statements(
        block,
        Map.put(inner_env, :boundary, boundary_id),
        &process_statement/2
      )

    {boundary_steps ++ block_steps, restore_boundary_scope(env, block_env)}
  end

  defp get_boundary_id(steps) do
    case List.last(steps) do
      {:boundary, %{id: id}} -> id
      _ -> nil
    end
  end

  defp restore_boundary_scope(original_env, current_env) do
    case Map.fetch(original_env, :boundary) do
      {:ok, id} -> Map.put(current_env, :boundary, id)
      :error -> Map.delete(current_env, :boundary)
    end
  end

  defp empty_env, do: %{nodes: %{}, boundaries: %{}}

  defp record_boundary(env, var, boundary_id) do
    atom_id = String.to_atom(boundary_id)

    env
    |> put_in([:boundaries, boundary_id], boundary_id)
    |> put_in([:boundaries, atom_id], boundary_id)
    |> then(fn env ->
      if var, do: put_in(env, [:boundaries, var], boundary_id), else: env
    end)
  end

  defp statement_steps({:=, meta, [{var, _, context}, constructor]}, env)
       when is_atom(var) and is_atom(context) do
    cond do
      boundary_constructor?(constructor) ->
        boundary = boundary_from_constructor(constructor, var, meta)
        {[{:boundary, boundary}], record_boundary(env, var, boundary.id)}

      node_constructor?(constructor) ->
        node = node_from_constructor(constructor, var, env, meta)
        env = env |> put_in([:nodes, var], node.id) |> put_in([:nodes, node.id], node.id)
        {[{:node, node}], env}

      true ->
        raise ArgumentError,
              "expected threat-model constructor, got #{Macro.to_string(constructor)}#{line_suffix(meta)}"
    end
  end

  defp statement_steps({:edge, meta, [edge_ast, label, opts]}, env)
       when is_binary(label) and is_list(opts) do
    opts = [label: label] ++ normalize_edge_opts(opts)
    {edge, nodes} = edge_from_ast(edge_ast, opts, env, meta)
    {edge_declaration_steps(nodes, edge), env}
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

      name in @boundary_verbs ->
        boundary = boundary_from_constructor(ast, nil, meta)
        env = record_boundary(env, nil, boundary.id)
        {[{:boundary, boundary}], env}

      Map.has_key?(@node_builders, name) ->
        node = node_from_constructor(ast, nil, env, meta)
        env = put_in(env.nodes[node.id], node.id)
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

  defp typed_edge_args!(_name, [edge_ast, opts], _meta) when is_list(opts), do: {edge_ast, opts}
  defp typed_edge_args!(_name, [edge_ast], _meta), do: {edge_ast, []}

  defp typed_edge_args!(name, args, meta) do
    raise ArgumentError,
          "unsupported threat-model edge form `#{name}/#{length(args)}`#{line_suffix(meta)}; " <>
            "use `#{name} from ~> to`, `#{name} from ~> to, label`, or `#{name} from ~> to, opts`"
  end

  defp typed_edge_statement(name, {edge_ast, opts}, env, meta) do
    opts = opts |> normalize_edge_opts() |> edge_semantic_opts(name)
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

  defp modifier_opt({name, _meta, [label, opts]}, acc)
       when name in @edge_verbs and is_binary(label) and is_list(opts) do
    opts
    |> Keyword.merge(acc)
    |> edge_semantic_opts(name)
    |> Keyword.put(:label, label)
    |> normalize_edge_opts()
  end

  defp modifier_opt({name, _meta, [opts]}, acc)
       when name in @edge_verbs and is_list(opts) do
    opts
    |> Keyword.merge(acc)
    |> edge_semantic_opts(name)
    |> normalize_edge_opts()
  end

  defp modifier_opt({name, _meta, [label, opts]}, acc)
       when name in [:on, :label, :edge] and is_binary(label) and is_list(opts) do
    opts = [label: label] ++ normalize_edge_opts(opts)
    Keyword.merge(acc, opts)
  end

  defp modifier_opt({name, _meta, [opts]}, acc)
       when name in [:on, :label, :edge] and is_list(opts) do
    Keyword.merge(acc, normalize_edge_opts(opts))
  end

  defp modifier_opt({name, _meta, [value]}, acc)
       when name in [:on, :label, :edge] and is_binary(value) do
    Keyword.put(acc, :label, value)
  end

  defp modifier_opt({:protocol, _meta, [value]}, acc), do: Keyword.put(acc, :protocol, value)

  defp modifier_opt({:encrypted, _meta, [value]}, acc) when is_boolean(value),
    do: Keyword.put(acc, :encrypted, value)

  defp modifier_opt({:encrypted, _meta, []}, acc), do: Keyword.put(acc, :encrypted, true)
  defp modifier_opt({:unencrypted, _meta, []}, acc), do: Keyword.put(acc, :encrypted, false)

  defp modifier_opt({name, _meta, []}, acc) when name in @edge_verbs do
    edge_semantic_opts(acc, name)
  end

  defp modifier_opt({name, _meta, [value]}, acc) when name in @edge_verbs and is_binary(value) do
    acc
    |> edge_semantic_opts(name)
    |> Keyword.put(:label, value)
  end

  defp modifier_opt({:with, _meta, [value]}, acc) when is_binary(value),
    do: Keyword.put(acc, :label, value)

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported threat-model edge modifier: #{Macro.to_string(other)}; " <>
            "use `flow(value)`, `encrypted(value)`, `unencrypted(value)`, `on(value)`, `protocol(value)`, or `label(value)`"
  end

  defp edge_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    from_endpoint = endpoint_id(from_ast, env, meta)
    to_endpoint = endpoint_id(to_ast, env, meta)

    {edge_endpoint_ids(from_endpoint, to_endpoint),
     declared_endpoint_nodes(from_endpoint, to_endpoint)}
    |> edge_and_nodes(opts)
  end

  defp edge_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in threat-model DSL, got #{Macro.to_string(other)}#{line_suffix(meta)}"
  end

  defp edge_endpoint_ids({from, _from_node}, {to, _to_node}), do: {from, to}

  defp declared_endpoint_nodes({_from, from_node}, {_to, to_node}) do
    [from_node, to_node]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp edge_and_nodes({{from, to}, nodes}, opts) do
    {%{from: from, to: to, opts: normalize_edge_opts(opts)}, nodes}
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env.nodes, var) do
      {:ok, id} ->
        {id, nil}

      :error ->
        raise ArgumentError, "unknown threat-model node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, env, meta)
      {node.id, node}
    else
      raise ArgumentError, "unknown threat-model node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported threat-model edge endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `api = process(\"API\")`"
  end

  defp node_from_constructor({name, meta, args}, var, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError, "unknown threat-model node constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    opts = resolve_boundary_option(opts, :boundary, env, meta)
    opts = maybe_inherit_boundary(opts, env)
    {id, opts} = node_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
  end

  defp maybe_inherit_boundary(opts, %{boundary: boundary}) when not is_nil(boundary) do
    Keyword.put_new(opts, :boundary, boundary)
  end

  defp maybe_inherit_boundary(opts, _env), do: opts

  defp boundary_from_constructor({name, meta, args}, var, _statement_meta)
       when name in @boundary_verbs and is_list(args) do
    {opts, positional} = pop_trailing_opts(args)
    {id, opts} = boundary_id_and_opts(var, positional, opts, meta)
    %{id: id, opts: opts}
  end

  defp node_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "threat-model node constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline threat-model node constructors need a label/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp boundary_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "threat-model boundary constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {to_string(explicit_id), maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {to_string(var), maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {boundary_id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline threat-model boundary constructors need a label/id or `id:` option#{line_suffix(meta)}"
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
          "inline threat-model node label/id must be a string or atom, got #{inspect(other)}"
  end

  defp boundary_id_from_label(id) when is_atom(id), do: to_string(id)
  defp boundary_id_from_label(id) when is_binary(id), do: id |> slug_atom() |> to_string()

  defp boundary_id_from_label(other) do
    raise ArgumentError,
          "inline threat-model boundary label/id must be a string or atom, got #{inspect(other)}"
  end

  defp resolve_boundary_option(opts, key, env, meta) do
    Keyword.update(opts, key, nil, &resolve_boundary_reference(&1, env, key, meta))
    |> Keyword.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp resolve_boundary_reference({var, _meta, context}, env, key, meta)
       when is_atom(var) and is_atom(context) do
    case Map.fetch(env.boundaries, var) do
      {:ok, id} ->
        id

      :error ->
        raise ArgumentError,
              "unknown threat-model boundary variable `#{var}` in `#{key}:`#{line_suffix(meta)}"
    end
  end

  defp resolve_boundary_reference(value, env, _key, _meta) when is_atom(value) do
    Map.get(env.boundaries, value, to_string(value))
  end

  defp resolve_boundary_reference(value, env, _key, _meta) when is_binary(value) do
    Map.get(env.boundaries, value, value)
  end

  defp resolve_boundary_reference(value, _env, _key, _meta), do: value

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
    Enum.reduce(@edge_verbs -- [:encrypted, :unencrypted], opts, fn key, acc ->
      {value, acc} = Keyword.pop(acc, key)

      if value == nil do
        acc
      else
        acc |> edge_semantic_opts(key) |> Keyword.put_new(:label, value)
      end
    end)
  end

  defp edge_semantic_opts(opts, :encrypted), do: Keyword.put(opts, :encrypted, true)
  defp edge_semantic_opts(opts, :unencrypted), do: Keyword.put(opts, :encrypted, false)
  defp edge_semantic_opts(opts, _name), do: opts

  defp boundary_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: name in @boundary_verbs

  defp boundary_constructor?(_other), do: false

  defp node_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(@node_builders, name)

  defp node_constructor?(_other), do: false

  defp pipe_step({:boundary, %{id: id, opts: opts}}, acc) do
    quote do
      Choreo.ThreatModel.add_trust_boundary(
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.ThreatModel, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, opts: opts}}, acc) do
    quote do
      Choreo.ThreatModel.data_flow(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in threat-model DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
  end

  # Autocomplete helper stubs
  for verb <- [
        :actor,
        :api,
        :boundary,
        :bucket,
        :cache,
        :client,
        :data_flow,
        :data_store,
        :database,
        :db,
        :edge,
        :encrypted,
        :external,
        :external_entity,
        :flow,
        :function,
        :label,
        :on,
        :process,
        :protocol,
        :queue,
        :reads,
        :sends,
        :service,
        :store,
        :third_party,
        :trust_boundary,
        :unencrypted,
        :user,
        :worker,
        :writes,
        :zone
      ] do
    def unquote(verb)(_arg1 \\ nil, _arg2 \\ nil, _opts \\ []) do
      raise "DSL constructor `#{unquote(verb)}` must be called inside a DSL block"
    end
  end
end
