defmodule Choreo.Lab.DSL.Dependency do
  import Choreo.Lab.DSL.Compiler

  @moduledoc """
  Experimental Livebook-friendly DSL for sketching software dependency graphs.

  This Lab DSL compiles to the stable, pipe-first `Choreo.Dependency` builders and
  returns an ordinary `%Choreo.Dependency{}`. It is useful for quick architecture
  sketches, refactoring conversations, onboarding maps, and interview explanations
  of coupling between applications, modules, libraries, interfaces, and tests.

  ## Examples

      iex> import Choreo.Lab.DSL.Dependency
      ...> deps = dependency do
      ...>   core = cluster("Core")
      ...>   api = application("API Gateway")
      ...>   auth = module("Auth", cluster: core)
      ...>   contract = interface("Auth Behaviour")
      ...>   phoenix = library("Phoenix")
      ...>
      ...>   api ~> phoenix |> uses("HTTP stack")
      ...>   api ~> auth |> calls("validates token")
      ...>   auth ~> contract |> implements("implements callbacks")
      ...> end
      iex> Enum.sort(Choreo.Dependency.nodes(deps))
      [:api, :auth, :contract, :phoenix]

  Edges can use generic, typed, or pipe-modified forms:

      api ~> auth
      api ~> auth |> calls("validates token")
      edge api ~> phoenix, uses: "framework"
      imports module_a ~> module_b, "alias/import"
      dev app ~> test_lib, "test helper"
  """

  @type node_decl :: %{id: Yog.node_id(), builder: atom(), opts: keyword()}
  @type cluster_decl :: %{id: String.t(), opts: keyword()}
  @type edge_decl :: %{from: Yog.node_id(), to: Yog.node_id(), opts: keyword()}

  @node_verbs [
    :application,
    :app,
    :service,
    :library,
    :lib,
    :package,
    :dependency,
    :module,
    :component,
    :interface,
    :contract,
    :protocol,
    :test,
    :spec,
    :test_suite
  ]

  @node_builders %{
    application: :add_application,
    app: :add_application,
    service: :add_application,
    library: :add_library,
    lib: :add_library,
    package: :add_library,
    dependency: :add_library,
    module: :add_module,
    component: :add_module,
    interface: :add_interface,
    contract: :add_interface,
    protocol: :add_interface,
    test: :add_test,
    spec: :add_test,
    test_suite: :add_test
  }

  @cluster_verbs [:cluster, :group, :layer]
  @edge_verbs [:depends, :depends_on, :uses, :imports, :calls, :inherits, :implements, :dev]

  @edge_type_aliases %{
    depends: :uses,
    depends_on: :uses,
    uses: :uses,
    imports: :imports,
    calls: :calls,
    inherits: :inherits,
    implements: :inherits,
    dev: :dev
  }

  @doc """
  Returns the vocabulary supported by the dependency DSL.

      iex> taxonomy = Choreo.Lab.DSL.Dependency.taxonomy()
      iex> :application in taxonomy.nodes
      true
      iex> :cluster in taxonomy.clusters
      true
      iex> :calls in taxonomy.edges
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
      edges: [:~>, :edge | @edge_verbs],
      modifiers: [:on, :label | @edge_verbs],
      options: [:label, :with, :id, :description, :cluster, :parent, :type | @edge_verbs]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: map()
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.Dependency{}` from a compact Lab DSL block.
  """
  defmacro dependency(do: block), do: compile(block)
  defmacro dependency(opts, do: block), do: compile(block, opts)

  defp compile(block, opts \\ []) do
    {steps_reversed, _env} =
      block
      |> statements()
      |> Enum.reduce({[], empty_env()}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {Enum.reverse(statement_steps, steps), env}
      end)

    Enum.reduce(
      Enum.reverse(steps_reversed),
      quote(do: Choreo.Dependency.new(unquote(Macro.escape(opts)))),
      &pipe_step/2
    )
  end

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
              "expected dependency constructor, got #{Macro.to_string(constructor)}#{line_suffix(meta)}"
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
          "unsupported dependency edge form `#{name}/#{length(args)}`#{line_suffix(meta)}; " <>
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
          "unsupported dependency edge modifier: #{Macro.to_string(other)}; " <>
            "use `on(value)`, `uses(value)`, `imports(value)`, `calls(value)`, or `dev(value)`"
  end

  defp edge_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, to, declared_nodes} = dependency_endpoints(from_ast, to_ast, env, meta)
    {%{from: from, to: to, opts: normalize_edge_opts(opts)}, declared_nodes}
  end

  defp edge_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in dependency DSL, got #{Macro.to_string(other)}" <>
            line_suffix(meta)
  end

  defp dependency_endpoints(from_ast, to_ast, env, meta) do
    {from, maybe_from_node} = endpoint_id(from_ast, env, meta)
    {to, maybe_to_node} = endpoint_id(to_ast, env, meta)
    {from, to, declared_endpoint_nodes(maybe_from_node, maybe_to_node)}
  end

  defp declared_endpoint_nodes(from_node, to_node) do
    [from_node, to_node]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env.nodes, var) do
      {:ok, id} ->
        {id, nil}

      :error ->
        raise ArgumentError, "unknown dependency node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, env, meta)
      {node.id, node}
    else
      raise ArgumentError, "unknown dependency node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported dependency edge endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `api = application(\"API\")`"
  end

  defp node_from_constructor({name, meta, args}, var, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError, "unknown dependency node constructor `#{name}`#{line_suffix(meta)}"

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
    %{id: id, opts: opts}
  end

  defp node_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "dependency node constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline dependency node constructors need a label/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp cluster_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "dependency cluster constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {to_string(explicit_id), maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {to_string(var), maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {cluster_id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline dependency cluster constructors need a label/id or `id:` option#{line_suffix(meta)}"
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
          "inline dependency node label/id must be a string or atom, got #{inspect(other)}"
  end

  defp cluster_id_from_label(id) when is_atom(id), do: to_string(id)
  defp cluster_id_from_label(id) when is_binary(id), do: id |> slug_atom() |> to_string()

  defp cluster_id_from_label(other) do
    raise ArgumentError,
          "inline dependency cluster label/id must be a string or atom, got #{inspect(other)}"
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
              "unknown dependency cluster variable `#{var}` in `#{key}:`#{line_suffix(meta)}"
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

      if value == nil do
        acc
      else
        acc |> edge_type_opts(key) |> Keyword.put_new(:label, value)
      end
    end)
  end

  defp edge_type_opts(opts, name) do
    Keyword.put(opts, :type, Map.fetch!(@edge_type_aliases, name))
  end

  defp cluster_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: name in @cluster_verbs

  defp cluster_constructor?(_other), do: false

  defp node_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(@node_builders, name)

  defp node_constructor?(_other), do: false

  defp pipe_step({:cluster, %{id: id, opts: opts}}, acc) do
    quote do
      Choreo.Dependency.add_cluster(
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.Dependency, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, opts: opts}}, acc) do
    quote do
      Choreo.Dependency.depends_on(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in dependency DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
  end

  # Autocomplete helper stubs
  for verb <- [
        :app,
        :application,
        :calls,
        :cluster,
        :component,
        :contract,
        :depends,
        :depends_on,
        :dev,
        :group,
        :implements,
        :imports,
        :inherits,
        :interface,
        :layer,
        :lib,
        :library,
        :module,
        :package,
        :protocol,
        :service,
        :spec,
        :test_suite,
        :uses
      ] do
    def unquote(verb)(_arg1 \\ nil, _arg2 \\ nil, _opts \\ []) do
      raise "DSL constructor `#{unquote(verb)}` must be called inside a DSL block"
    end
  end
end
