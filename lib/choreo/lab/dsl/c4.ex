defmodule Choreo.Lab.DSL.C4 do
  @moduledoc """
  Experimental Livebook-friendly DSL for sketching C4 models.

  This Lab DSL compiles to the stable, pipe-first `Choreo.C4` builders and
  returns an ordinary `%Choreo.C4{}`. It keeps C4 nouns explicit — people,
  software systems, containers, and components — while relationship verbs make
  quick architecture sketches read naturally in Livebook.

  ## Examples

      iex> import Choreo.Lab.DSL.C4
      ...> model = c4 do
      ...>   customer = person("Customer", description: "API consumer")
      ...>   gateway = system("API Gateway", scope: :in, description: "Routes tenant API traffic")
      ...>   api = container("Gateway API", parent: gateway, technology: "Phoenix")
      ...>   db = container("Tenant DB", parent: gateway, technology: "Postgres")
      ...>
      ...>   customer ~> api |> uses("Submits API requests", technology: "HTTPS")
      ...>   api ~> db |> reads("Tenant config", technology: "SQL")
      ...>   scope gateway
      ...> end
      iex> Choreo.C4.scope(model)
      :gateway
      iex> model.graph.nodes[:api].parent
      :gateway
      iex> [{_, _, _, meta} | _] = Choreo.C4.edges_with_meta(model)
      iex> meta.label
      "Submits API requests"

  Relationship edges can use generic labels, typed verbs, or explicit `edge`:

      user ~> system |> uses("Uses")
      api ~> db |> reads("Reads tenant config", technology: "SQL")
      edge api ~> worker, calls: "Dispatches job"
      sends api ~> queue, "Publishes event", technology: "Kafka"

  Parent and scope options can use variables bound earlier in the block:

      app = system("Application", scope: :in)
      api = container("API", parent: app)
      auth = component("Auth Controller", parent: api)
      scope app
  """

  @type cluster_decl :: %{id: String.t(), opts: keyword()}
  @type node_decl :: %{id: Yog.node_id(), builder: atom(), opts: keyword()}
  @type edge_decl :: %{from: Yog.node_id(), to: Yog.node_id(), opts: keyword()}

  @cluster_verbs [:cluster, :boundary, :group]

  @node_verbs [
    :person,
    :user,
    :actor,
    :software_system,
    :system,
    :external_system,
    :container,
    :application,
    :app,
    :service,
    :database,
    :datastore,
    :component,
    :module
  ]

  @node_builders %{
    person: :add_person,
    user: :add_person,
    actor: :add_person,
    software_system: :add_software_system,
    system: :add_software_system,
    external_system: :add_software_system,
    container: :add_container,
    application: :add_container,
    app: :add_container,
    service: :add_container,
    database: :add_container,
    datastore: :add_container,
    component: :add_component,
    module: :add_component
  }

  @edge_verbs [
    :relates,
    :uses,
    :calls,
    :sends,
    :publishes,
    :consumes,
    :reads,
    :writes,
    :routes,
    :depends
  ]

  @doc """
  Returns the vocabulary supported by the C4 DSL.

  This is meant as a lightweight Livebook discovery helper when autocomplete is
  not enough.

      iex> taxonomy = Choreo.Lab.DSL.C4.taxonomy()
      iex> :person in taxonomy.nodes
      true
      iex> :container in taxonomy.nodes
      true
      iex> :uses in taxonomy.edges
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
      events: [:scope, :in_scope],
      modifiers: [:on, :label, :technology | @edge_verbs],
      options: [:label, :with, :id, :description, :technology, :parent, :scope | @edge_verbs]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: map()
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.C4{}` from a compact Lab DSL block.
  """
  defmacro c4(do: block), do: compile(block)
  defmacro c4(opts, do: block), do: compile(block, opts)

  defp compile(block, opts \\ []) do
    {steps, _env} =
      block
      |> statements()
      |> Enum.reduce({[], empty_env()}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {steps ++ statement_steps, env}
      end)

    Enum.reduce(steps, quote(do: Choreo.C4.new(unquote(Macro.escape(opts)))), &pipe_step/2)
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
              "expected C4 constructor, got #{Macro.to_string(constructor)}#{line_suffix(meta)}"
    end
  end

  defp statement_steps({:scope, meta, [node_ast]}, env), do: scope_statement(node_ast, env, meta)

  defp statement_steps({:in_scope, meta, [node_ast]}, env),
    do: scope_statement(node_ast, env, meta)

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

  for edge_name <- @edge_verbs do
    defp statement_steps({unquote(edge_name), meta, [edge_ast, label, opts]}, env)
         when is_binary(label) and is_list(opts) do
      typed_edge_statement(unquote(edge_name), edge_ast, [label: label] ++ opts, env, meta)
    end

    defp statement_steps({unquote(edge_name), meta, [edge_ast, label]}, env)
         when is_binary(label) do
      typed_edge_statement(unquote(edge_name), edge_ast, [label: label], env, meta)
    end

    defp statement_steps({unquote(edge_name), meta, [edge_ast, opts]}, env) when is_list(opts) do
      typed_edge_statement(unquote(edge_name), edge_ast, opts, env, meta)
    end

    defp statement_steps({unquote(edge_name), meta, [edge_ast]}, env) do
      typed_edge_statement(unquote(edge_name), edge_ast, [], env, meta)
    end
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
      Map.has_key?(cluster_builders(), name) ->
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

  defp scope_statement(node_ast, env, meta) do
    {id, node} = endpoint_id(node_ast, env, meta)
    {node |> node_steps() |> append_step({:scope, id}), env}
  end

  defp typed_edge_statement(name, edge_ast, opts, env, meta) do
    opts = opts |> normalize_edge_opts() |> put_edge_label_for(name, nil)
    {edge, nodes} = edge_from_ast(edge_ast, opts, env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp edge_declaration_steps(nodes, edge) do
    nodes
    |> Enum.reduce([{:edge, edge}], fn node, steps -> [{:node, node} | steps] end)
    |> Enum.reverse()
  end

  defp node_steps(nil), do: []
  defp node_steps(node), do: [{:node, node}]

  defp append_step(steps, step),
    do: steps |> Enum.reverse() |> then(&[step | &1]) |> Enum.reverse()

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

  defp modifier_opt({:technology, _meta, [value]}, acc), do: Keyword.put(acc, :technology, value)

  defp modifier_opt({name, _meta, []}, acc) when name in @edge_verbs do
    put_edge_label_for(acc, name, nil)
  end

  defp modifier_opt({name, _meta, [value]}, acc) when name in @edge_verbs do
    put_edge_label_for(acc, name, value)
  end

  defp modifier_opt({name, _meta, [value, opts]}, acc)
       when name in @edge_verbs and is_list(opts) do
    acc
    |> Keyword.merge(opts)
    |> put_edge_label_for(name, value)
  end

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported C4 relationship modifier: #{Macro.to_string(other)}; " <>
            "use `on(value)`, `uses(value)`, `calls(value)`, or `technology(value)`"
  end

  defp edge_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, from_node} = endpoint_id(from_ast, env, meta)
    {to, to_node} = endpoint_id(to_ast, env, meta)
    nodes = [from_node, to_node] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)
    {%{from: from, to: to, opts: normalize_edge_opts(opts)}, nodes}
  end

  defp edge_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in C4 DSL, got #{Macro.to_string(other)}#{line_suffix(meta)}"
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env.nodes, var) do
      {:ok, id} -> {id, nil}
      :error -> raise ArgumentError, "unknown C4 node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, env, meta)
      {node.id, node}
    else
      raise ArgumentError, "unknown C4 node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported C4 relationship endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `api = container(\"API\")`"
  end

  defp node_from_constructor({name, meta, args}, var, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError, "unknown C4 node constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    opts = resolve_node_references(opts, env, meta)
    {id, opts} = node_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
  end

  defp cluster_from_constructor({name, meta, args}, var, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder = Map.fetch!(cluster_builders(), name)
    {opts, positional} = pop_trailing_opts(args)
    opts = resolve_cluster_option(opts, :parent, env, meta)
    {id, opts} = cluster_id_and_opts(var, positional, opts, meta)
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
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "node constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline C4 node constructors need a label/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp cluster_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "cluster constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {ensure_cluster_prefix(explicit_id), maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {ensure_cluster_prefix(var), maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)

        {label_or_id |> cluster_id_from_label() |> ensure_cluster_prefix(),
         maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline C4 cluster constructors need a label/id or `id:` option#{line_suffix(meta)}"
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

  defp id_from_label(other),
    do:
      raise(
        ArgumentError,
        "inline C4 node label/id must be a string or atom, got #{inspect(other)}"
      )

  defp cluster_id_from_label(id) when is_atom(id), do: to_string(id)
  defp cluster_id_from_label(id) when is_binary(id), do: id |> slug_atom() |> to_string()

  defp cluster_id_from_label(other),
    do:
      raise(
        ArgumentError,
        "inline C4 cluster label/id must be a string or atom, got #{inspect(other)}"
      )

  defp ensure_cluster_prefix(id) do
    id = to_string(id)
    if String.starts_with?(id, "cluster_"), do: id, else: "cluster_" <> id
  end

  defp slug_atom(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> raise ArgumentError, "cannot derive a C4 node id from an empty label"
      slug -> String.to_atom(slug)
    end
  end

  defp resolve_node_references(opts, env, meta) do
    resolve_node_option(opts, :parent, env, meta)
  end

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
        raise ArgumentError, "unknown C4 node variable `#{var}` in `#{key}:`#{line_suffix(meta)}"
    end
  end

  defp resolve_node_reference(value, _env, _key, _meta), do: value

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
              "unknown C4 cluster variable `#{var}` in `#{key}:`#{line_suffix(meta)}"
    end
  end

  defp resolve_cluster_reference(value, _env, _key, _meta), do: value

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
      if value == nil, do: acc, else: put_edge_label_for(acc, key, value)
    end)
  end

  defp put_edge_label_for(opts, :relates, nil), do: opts
  defp put_edge_label_for(opts, _name, nil), do: opts
  defp put_edge_label_for(opts, _name, value), do: Keyword.put_new(opts, :label, value)

  defp cluster_builders, do: %{cluster: :add_cluster, boundary: :add_cluster, group: :add_cluster}

  defp cluster_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(cluster_builders(), name)

  defp cluster_constructor?(_other), do: false

  defp node_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(@node_builders, name)

  defp node_constructor?(_other), do: false

  defp pipe_step({:cluster, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.C4, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.C4, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, opts: opts}}, acc) do
    quote do
      Choreo.C4.add_relationship(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp pipe_step({:scope, id}, acc) do
    quote do
      Choreo.C4.set_scope(unquote(acc), unquote(Macro.escape(id)))
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in C4 DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
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
