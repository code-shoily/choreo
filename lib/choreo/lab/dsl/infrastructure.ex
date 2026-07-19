defmodule Choreo.Lab.DSL.Infrastructure do
  @moduledoc """
  Experimental Livebook-friendly DSL for sketching infrastructure diagrams.

  This module is an incubating Lab syntax layer over the stable, pipe-first
  `Choreo` infrastructure builders. It returns a normal `%Choreo{}` system, so
  the result can be rendered and analysed with the same functions as any other
  Choreo graph.

  The DSL is intentionally strict about references: bind nodes to variables and
  reuse those variables in edges. Typos in labels render as written; typos in
  variable names fail during macro expansion.

  ## Examples

      iex> import Choreo.Lab.DSL.Infrastructure
      ...> system = infrastructure do
      ...>   client = user("API Client")
      ...>   api = gateway("API Gateway")
      ...>   redis = cache("Redis", kind: :redis)
      ...>   db = database("Postgres", kind: :postgres)
      ...>
      ...>   client ~> api
      ...>   api ~> redis |> on("checks quota")
      ...>   edge api ~> db, with: "reads/writes"
      ...> end
      iex> system.graph.nodes[:api].label
      "API Gateway"
      iex> system.graph.nodes[:redis].node_type
      :cache
      iex> system.edge_meta |> Map.values() |> Enum.map(& &1.label) |> Enum.sort()
      [nil, "checks quota", "reads/writes"]

  Supported cluster constructors:

    * `cluster/1`
    * `vpc/1`
    * `public_subnet/1`, `subnet_public/1`
    * `private_subnet/1`, `subnet_private/1`

  Supported node constructors:

    * `user/1`, `client/1`
    * `gateway/1`, `load_balancer/1`, `lb/1`
    * `service/1`
    * `compute/1`
    * `database/1`, `db/1`
    * `managed_db/1`
    * `cache/1`
    * `queue/1`
    * `storage/1`, `object_store/1`
    * `internet/1`
    * `network/1`, `external/1`
    * `node/1`, `custom/1`

  Cluster variables can be used in `parent:` and node `cluster:` options:

      prod = vpc("Production VPC")
      private = private_subnet("Private Subnet", parent: prod)
      api = service("API", cluster: private)

  Edge labels can use either pipe modifiers or the explicit `edge` form:

      api ~> db |> on("reads")
      api ~> db |> label("reads")
      edge api ~> db, "reads"
      edge api ~> db, label: "reads"
      edge api ~> db, with: "reads"
  """

  @type cluster_decl :: %{id: String.t(), builder: atom(), opts: keyword()}
  @type node_decl :: %{id: Yog.node_id(), builder: atom(), opts: keyword()}
  @type edge_decl :: %{from: Yog.node_id(), to: Yog.node_id(), opts: keyword()}

  @cluster_verbs [
    :cluster,
    :vpc,
    :public_subnet,
    :subnet_public,
    :private_subnet,
    :subnet_private
  ]

  @cluster_builders %{
    cluster: :add_cluster,
    vpc: :add_vpc,
    public_subnet: :add_subnet_public,
    subnet_public: :add_subnet_public,
    private_subnet: :add_subnet_private,
    subnet_private: :add_subnet_private
  }

  @node_verbs [
    :user,
    :client,
    :gateway,
    :load_balancer,
    :lb,
    :service,
    :compute,
    :database,
    :db,
    :managed_db,
    :cache,
    :queue,
    :storage,
    :object_store,
    :internet,
    :network,
    :external,
    :node,
    :custom
  ]

  @node_builders %{
    user: :add_user,
    client: :add_user,
    gateway: :add_load_balancer,
    load_balancer: :add_load_balancer,
    lb: :add_load_balancer,
    service: :add_service,
    compute: :add_compute,
    database: :add_database,
    db: :add_database,
    managed_db: :add_managed_db,
    cache: :add_cache,
    queue: :add_queue,
    storage: :add_storage,
    object_store: :add_storage,
    internet: :add_internet,
    network: :add_network,
    external: :add_network,
    node: :add_node,
    custom: :add_node
  }

  @doc """
  Returns the vocabulary supported by the infrastructure DSL.

  This is meant as a lightweight Livebook discovery helper when autocomplete is
  not enough.

      iex> taxonomy = Choreo.Lab.DSL.Infrastructure.taxonomy()
      iex> :vpc in taxonomy.clusters
      true
      iex> :service in taxonomy.nodes
      true
      iex> :~> in taxonomy.edges
      true
      iex> :on in taxonomy.modifiers
      true
  """
  @spec taxonomy() :: %{
          clusters: [atom()],
          nodes: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def taxonomy do
    %{
      clusters: @cluster_verbs,
      nodes: @node_verbs,
      edges: [:~>, :edge],
      modifiers: [:on, :label],
      options: [:label, :with, :id, :kind, :cluster, :parent, :description]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: %{
          clusters: [atom()],
          nodes: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo{}` infrastructure sketch from a compact Lab DSL block.
  """
  defmacro infrastructure(do: block) do
    compile(block)
  end

  defmacro infrastructure(opts, do: block) do
    compile(block, opts)
  end

  defp compile(block, opts \\ []) do
    {steps, _env} =
      block
      |> statements()
      |> Enum.reduce({[], empty_env()}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {steps ++ statement_steps, env}
      end)

    Enum.reduce(steps, quote(do: Choreo.new(unquote(Macro.escape(opts)))), &pipe_step/2)
  end

  defp statements({:__block__, _meta, list}), do: list
  defp statements(nil), do: []
  defp statements(single), do: [single]

  defp empty_env, do: %{nodes: %{}, clusters: %{}}

  # variable = constructor("Label", opts)
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
              "expected infrastructure constructor, got #{Macro.to_string(constructor)}#{line_suffix(meta)}"
    end
  end

  # edge api ~> db, "reads"
  defp statement_steps({:edge, meta, [edge_ast, label]}, env) when is_binary(label) do
    {edge, nodes} = edge_from_ast(edge_ast, [label: label], env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  # edge api ~> db, label: "reads"
  defp statement_steps({:edge, meta, [edge_ast, opts]}, env) when is_list(opts) do
    {edge, nodes} = edge_from_ast(edge_ast, normalize_edge_opts(opts), env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  # edge api ~> db
  defp statement_steps({:edge, meta, [edge_ast]}, env) do
    {edge, nodes} = edge_from_ast(edge_ast, [], env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  # api ~> db or api ~> db |> on("label")
  defp statement_steps({:|>, _meta, _args} = ast, env) do
    {edge, nodes} = edge_from_piped_ast(ast, env)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp statement_steps({:~>, meta, _args} = ast, env) do
    {edge, nodes} = edge_from_ast(ast, [], env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  # inline cluster/node declaration, e.g. vpc("Prod") or service("API")
  defp statement_steps({name, meta, args} = ast, env) when is_atom(name) and is_list(args) do
    cond do
      Map.has_key?(@cluster_builders, name) ->
        cluster = cluster_from_constructor(ast, nil, env, meta)
        {[{:cluster, cluster}], env}

      Map.has_key?(@node_builders, name) ->
        node = node_from_constructor(ast, nil, env, meta)
        {[{:node, node}], env}

      true ->
        unsupported_statement!(ast, meta)
    end
  end

  defp statement_steps(other, _env) do
    unsupported_statement!(other, nil)
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

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported infrastructure edge modifier: #{Macro.to_string(other)}; " <>
            "use `on(value)` or `label(value)`"
  end

  defp edge_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, from_node} = endpoint_id(from_ast, env, meta)
    {to, to_node} = endpoint_id(to_ast, env, meta)
    nodes = [from_node, to_node] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)

    {%{from: from, to: to, opts: opts}, nodes}
  end

  defp edge_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in infrastructure DSL, got #{Macro.to_string(other)}" <>
            line_suffix(meta)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env.nodes, var) do
      {:ok, id} ->
        {id, nil}

      :error ->
        raise ArgumentError, "unknown infrastructure node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, env, meta)
      {node.id, node}
    else
      raise ArgumentError,
            "unknown infrastructure node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported infrastructure edge endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `api = service(\"API\")`"
  end

  defp node_from_constructor({name, meta, args}, var, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError,
              "unknown infrastructure node constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    opts = resolve_cluster_option(opts, :cluster, env, meta)

    {id, opts} = node_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
  end

  defp node_from_constructor(other, _var, _env, meta) do
    raise ArgumentError,
          "expected infrastructure node constructor, got #{Macro.to_string(other)}#{line_suffix(meta)}"
  end

  defp cluster_from_constructor({name, meta, args}, var, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@cluster_builders, name) ||
        raise ArgumentError,
              "unknown infrastructure cluster constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    opts = resolve_cluster_option(opts, :parent, env, meta)

    {id, opts} = cluster_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
  end

  defp cluster_from_constructor(other, _var, _env, meta) do
    raise ArgumentError,
          "expected infrastructure cluster constructor, got #{Macro.to_string(other)}#{line_suffix(meta)}"
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
              "inline infrastructure node constructors need a label/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp cluster_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "cluster constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {to_string(explicit_id), maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {to_string(var), maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {cluster_id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline infrastructure cluster constructors need a label/id or `id:` option#{line_suffix(meta)}"
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
          "inline infrastructure node label/id must be a string or atom, got #{inspect(other)}"
  end

  defp cluster_id_from_label(id) when is_atom(id), do: to_string(id)
  defp cluster_id_from_label(id) when is_binary(id), do: id |> slug_atom() |> to_string()

  defp cluster_id_from_label(other) do
    raise ArgumentError,
          "inline infrastructure cluster label/id must be a string or atom, got #{inspect(other)}"
  end

  defp slug_atom(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> raise ArgumentError, "cannot derive an infrastructure node id from an empty label"
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
              "unknown infrastructure cluster variable `#{var}` in `#{key}:`#{line_suffix(meta)}"
    end
  end

  defp resolve_cluster_reference(value, _env, _key, _meta), do: value

  defp normalize_edge_opts(opts) do
    {with_label, opts} = Keyword.pop(opts, :with)

    if with_label != nil do
      Keyword.put_new(opts, :label, with_label)
    else
      opts
    end
  end

  defp cluster_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(@cluster_builders, name)

  defp cluster_constructor?(_other), do: false

  defp node_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(@node_builders, name)

  defp node_constructor?(_other), do: false

  defp pipe_step({:cluster, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, opts: opts}}, acc) do
    quote do
      Choreo.connect(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in infrastructure DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
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
