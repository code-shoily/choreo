defmodule Choreo.Lab.DSL.Dataflow do
  import Choreo.Lab.DSL.Compiler

  @moduledoc """
  Experimental Livebook-friendly DSL for sketching dataflow pipelines.

  This Lab DSL compiles to the stable, pipe-first `Choreo.Dataflow` builders and
  returns an ordinary `%Choreo.Dataflow{}`. It uses node constructors for dataflow
  stages and typed edge vocabulary for normal, error, retry, and dead-letter paths.

  ## Examples

      iex> import Choreo.Lab.DSL.Dataflow
      ...> pipeline = dataflow do
      ...>   ingest = source("Kafka Ingest", rate: "10k/s")
      ...>   parser = transform("JSON Parser", latency_ms: 5)
      ...>   valid = conditional("Valid?")
      ...>   postgres = sink("Postgres")
      ...>   dlq = sink("Dead Letter Queue")
      ...>
      ...>   ingest ~> parser |> emits("raw events")
      ...>   parser ~> valid |> emits("parsed events")
      ...>   valid ~> postgres |> writes("valid records")
      ...>   dead_letter valid ~> dlq, "invalid records"
      ...> end
      iex> pipeline.graph.nodes[:ingest].node_type
      :source
      iex> pipeline.edge_meta[{:valid, :dlq}].path_type
      :dead_letter

  Edge labels can use generic labels, typed data labels, or explicit path types:

      source ~> transform |> on("events")
      edge source ~> transform, data_type: "events"
      emits source ~> transform, "events"
      error transform ~> sink, "invalid input"
      retry transform ~> buffer, "retry later"
      dead_letter transform ~> dlq, "poison message"
  """

  @type cluster_decl :: %{id: String.t(), opts: keyword()}
  @type node_decl :: %{id: Yog.node_id(), builder: atom(), opts: keyword()}
  @type edge_decl :: %{from: Yog.node_id(), to: Yog.node_id(), opts: keyword()}

  @cluster_verbs [:cluster, :stage, :lane]

  @node_verbs [
    :source,
    :input,
    :producer,
    :sink,
    :output,
    :consumer,
    :transform,
    :process,
    :processor,
    :buffer,
    :queue,
    :topic,
    :conditional,
    :decision,
    :split,
    :merge,
    :join
  ]

  @node_builders %{
    source: :add_source,
    input: :add_source,
    producer: :add_source,
    sink: :add_sink,
    output: :add_sink,
    consumer: :add_sink,
    transform: :add_transform,
    process: :add_transform,
    processor: :add_transform,
    buffer: :add_buffer,
    queue: :add_buffer,
    topic: :add_buffer,
    conditional: :add_conditional,
    decision: :add_conditional,
    split: :add_conditional,
    merge: :add_merge,
    join: :add_merge
  }

  @edge_verbs [
    :flow,
    :flows,
    :emits,
    :sends,
    :publishes,
    :consumes,
    :reads,
    :writes,
    :routes,
    :normal,
    :error,
    :retry,
    :dead_letter,
    :dlq
  ]

  @data_label_edges [
    :flow,
    :flows,
    :emits,
    :sends,
    :publishes,
    :consumes,
    :reads,
    :writes,
    :routes
  ]

  @path_edges %{
    normal: :normal,
    error: :error,
    retry: :retry,
    dead_letter: :dead_letter,
    dlq: :dead_letter
  }

  @doc """
  Returns the vocabulary supported by the dataflow DSL.

  This is meant as a lightweight Livebook discovery helper when autocomplete is
  not enough.

      iex> taxonomy = Choreo.Lab.DSL.Dataflow.taxonomy()
      iex> :source in taxonomy.nodes
      true
      iex> :emits in taxonomy.edges
      true
      iex> :dead_letter in taxonomy.edges
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
      modifiers: [:on, :label, :data, :rate, :weight, :type, :edge_type, :edge | @edge_verbs],
      options: [
        :label,
        :with,
        :id,
        :cluster,
        :parent,
        :data_type,
        :rate,
        :path_type,
        :weight,
        :capacity,
        :latency_ms
      ]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: map()
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.Dataflow{}` from a compact Lab DSL block.
  """
  defmacro dataflow(do: block), do: compile(block)
  defmacro dataflow(opts, do: block), do: compile(block, opts)

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
      quote(do: Choreo.Dataflow.new(unquote(Macro.escape(opts)))),
      &pipe_step/2
    )
  end

  defp process_statement(statement, env) do
    case extract_do_block(statement) do
      {block, stripped_statement} when not is_nil(block) ->
        {parent_steps, inner_env_base} = statement_steps(stripped_statement, env)
        parent_id = get_parent_id_from_steps(parent_steps)

        {inner_steps, final_inner_env} =
          compile_block_statements(
            block,
            Map.put(inner_env_base, :cluster, parent_id),
            &process_statement/2
          )

        cluster_env =
          case Map.fetch(env, :cluster) do
            {:ok, c} -> Map.put(final_inner_env, :cluster, c)
            :error -> Map.delete(final_inner_env, :cluster)
          end

        {parent_steps ++ inner_steps, cluster_env}

      _ ->
        statement_steps(statement, env)
    end
  end

  defp get_parent_id_from_steps(steps) do
    case List.last(steps) do
      {:cluster, %{id: id}} -> id
      _ -> nil
    end
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
              "expected dataflow constructor, got #{Macro.to_string(constructor)}#{line_suffix(meta)}"
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
        {[{:cluster, cluster}], put_in(env.clusters[String.to_atom(cluster.id)], cluster.id)}

      Map.has_key?(@node_builders, name) ->
        node = node_from_constructor(ast, nil, env, meta)
        {[{:node, node}], put_in(env.nodes[node.id], node.id)}

      true ->
        unsupported_statement!(ast, meta)
    end
  end

  defp statement_steps(other, _env), do: unsupported_statement!(other, nil)

  defp typed_edge_statement(name, edge_ast, opts, env, meta) do
    opts =
      opts
      |> normalize_edge_opts()
      |> edge_type_opts(name)
      |> maybe_put_data_type(name)

    {edge, nodes} = edge_from_ast(edge_ast, opts, env, meta)
    {edge_declaration_steps(nodes, edge), env}
  end

  defp maybe_put_data_type(opts, name) when name in @data_label_edges do
    case Keyword.fetch(opts, :label) do
      {:ok, label} when is_binary(label) -> Keyword.put_new(opts, :data_type, label)
      _ -> opts
    end
  end

  defp maybe_put_data_type(opts, _name), do: opts

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

  defp modifier_opt({name, _meta, [value]}, acc)
       when name in [:on, :label] and is_binary(value) do
    Keyword.put(acc, :label, value)
  end

  defp modifier_opt({name, _meta, [opts]}, acc) when name in [:on, :label] and is_list(opts) do
    Keyword.merge(acc, normalize_edge_opts(opts))
  end

  defp modifier_opt({name, _meta, [value, opts]}, acc)
       when name in [:on, :label] and is_binary(value) and is_list(opts) do
    acc
    |> Keyword.put(:label, value)
    |> Keyword.merge(normalize_edge_opts(opts))
  end

  defp modifier_opt({:data, _meta, [value]}, acc) when is_binary(value) do
    acc
    |> Keyword.put(:data_type, value)
    |> Keyword.put_new(:label, value)
  end

  defp modifier_opt({:data, _meta, [opts]}, acc) when is_list(opts) do
    Keyword.merge(acc, normalize_edge_opts(opts))
  end

  defp modifier_opt({:data, _meta, [value, opts]}, acc)
       when is_binary(value) and is_list(opts) do
    acc
    |> Keyword.put(:data_type, value)
    |> Keyword.put_new(:label, value)
    |> Keyword.merge(normalize_edge_opts(opts))
  end

  defp modifier_opt({:rate, _meta, [value]}, acc), do: Keyword.put(acc, :rate, value)
  defp modifier_opt({:weight, _meta, [value]}, acc), do: Keyword.put(acc, :weight, value)

  defp modifier_opt({type_verb, _meta, [type]}, acc)
       when type_verb in [:type, :edge_type] and type in @edge_verbs do
    edge_type_opts(acc, type)
  end

  defp modifier_opt({type_verb, _meta, [type, label]}, acc)
       when type_verb in [:type, :edge_type] and type in @edge_verbs and is_binary(label) do
    acc
    |> edge_type_opts(type)
    |> put_edge_label_for(type, label)
  end

  defp modifier_opt({type_verb, _meta, [type, opts]}, acc)
       when type_verb in [:type, :edge_type] and type in @edge_verbs and is_list(opts) do
    acc
    |> edge_type_opts(type)
    |> Keyword.merge(normalize_edge_opts(opts))
  end

  defp modifier_opt({type_verb, _meta, [type, label, opts]}, acc)
       when type_verb in [:type, :edge_type] and type in @edge_verbs and is_binary(label) and
              is_list(opts) do
    acc
    |> edge_type_opts(type)
    |> put_edge_label_for(type, label)
    |> Keyword.merge(normalize_edge_opts(opts))
  end

  defp modifier_opt({:edge, _meta, []}, acc), do: acc

  defp modifier_opt({:edge, _meta, [label]}, acc) when is_binary(label) do
    Keyword.put(acc, :label, label)
  end

  defp modifier_opt({:edge, _meta, [opts]}, acc) when is_list(opts) do
    Keyword.merge(acc, normalize_edge_opts(opts))
  end

  defp modifier_opt({:edge, _meta, [label, opts]}, acc)
       when is_binary(label) and is_list(opts) do
    acc
    |> Keyword.put(:label, label)
    |> Keyword.merge(normalize_edge_opts(opts))
  end

  defp modifier_opt({name, _meta, []}, acc) when name in @edge_verbs do
    edge_type_opts(acc, name)
  end

  defp modifier_opt({name, _meta, [label]}, acc) when name in @edge_verbs and is_binary(label) do
    acc
    |> edge_type_opts(name)
    |> put_edge_label_for(name, label)
  end

  defp modifier_opt({name, _meta, [opts]}, acc) when name in @edge_verbs and is_list(opts) do
    acc
    |> edge_type_opts(name)
    |> Keyword.merge(normalize_edge_opts(opts))
  end

  defp modifier_opt({name, _meta, [label, opts]}, acc)
       when name in @edge_verbs and is_binary(label) and is_list(opts) do
    acc
    |> edge_type_opts(name)
    |> put_edge_label_for(name, label)
    |> Keyword.merge(normalize_edge_opts(opts))
  end

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported dataflow edge modifier: #{Macro.to_string(other)}; " <>
            "use `on(value)`, `emits(value)`, `error(value)`, `retry(value)`, or `data(value)`"
  end

  defp edge_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, from_node} = endpoint_id(from_ast, env, meta)
    {to, to_node} = endpoint_id(to_ast, env, meta)
    nodes = [from_node, to_node] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)
    opts = opts |> normalize_edge_opts() |> Keyword.put_new(:path_type, :normal)

    {%{from: from, to: to, opts: opts}, nodes}
  end

  defp edge_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in dataflow DSL, got #{Macro.to_string(other)}" <>
            line_suffix(meta)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env.nodes, var) do
      {:ok, id} -> {id, nil}
      :error -> raise ArgumentError, "unknown dataflow node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, env, meta)
      {node.id, node}
    else
      raise ArgumentError, "unknown dataflow node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported dataflow edge endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `parser = transform(\"Parser\")`"
  end

  defp node_from_constructor({name, meta, args}, var, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError, "unknown dataflow node constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)

    opts =
      case Map.fetch(env, :cluster) do
        {:ok, cluster_id} when not is_nil(cluster_id) ->
          Keyword.put_new(opts, :cluster, cluster_id)

        _ ->
          opts
      end

    opts = resolve_cluster_option(opts, :cluster, env, meta)
    {id, opts} = node_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
  end

  defp cluster_from_constructor({name, meta, args}, var, env, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder = Map.fetch!(cluster_builders(), name)
    {opts, positional} = pop_trailing_opts(args)

    opts =
      case Map.fetch(env, :cluster) do
        {:ok, cluster_id} when not is_nil(cluster_id) ->
          Keyword.put_new(opts, :parent, cluster_id)

        _ ->
          opts
      end

    opts = resolve_cluster_option(opts, :parent, env, meta)
    {id, opts} = cluster_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
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
              "inline dataflow node constructors need a label/id or `id:` option#{line_suffix(meta)}"
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
              "inline dataflow cluster constructors need a label/id or `id:` option#{line_suffix(meta)}"
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
          "inline dataflow node label/id must be a string or atom, got #{inspect(other)}"
  end

  defp cluster_id_from_label(id) when is_atom(id), do: to_string(id)
  defp cluster_id_from_label(id) when is_binary(id), do: id |> slug_atom() |> to_string()

  defp cluster_id_from_label(other) do
    raise ArgumentError,
          "inline dataflow cluster label/id must be a string or atom, got #{inspect(other)}"
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
              "unknown dataflow cluster variable `#{var}` in `#{key}:`#{line_suffix(meta)}"
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
        acc |> edge_type_opts(key) |> put_edge_label_for(key, value)
      end
    end)
  end

  defp edge_type_opts(opts, name) when name in @data_label_edges do
    Keyword.put_new(opts, :path_type, :normal)
  end

  defp edge_type_opts(opts, name) do
    case Map.fetch(@path_edges, name) do
      {:ok, path_type} -> Keyword.put(opts, :path_type, path_type)
      :error -> opts
    end
  end

  defp put_edge_label_for(opts, name, value) when name in @data_label_edges do
    opts
    |> Keyword.put_new(:data_type, value)
    |> Keyword.put_new(:label, value)
  end

  defp put_edge_label_for(opts, _name, value), do: Keyword.put_new(opts, :label, value)

  defp cluster_builders, do: %{cluster: :add_cluster, stage: :add_cluster, lane: :add_cluster}

  defp cluster_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(cluster_builders(), name)

  defp cluster_constructor?(_other), do: false

  defp node_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(@node_builders, name)

  defp node_constructor?(_other), do: false

  defp pipe_step({:cluster, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.Dataflow, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.Dataflow, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, opts: opts}}, acc) do
    quote do
      Choreo.Dataflow.connect(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in dataflow DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
  end

  # Autocomplete helper stubs
  for verb <- [
        :buffer,
        :cluster,
        :conditional,
        :consumer,
        :consumes,
        :data,
        :dead_letter,
        :decision,
        :dlq,
        :edge,
        :edge_type,
        :emits,
        :error,
        :flow,
        :flows,
        :input,
        :join,
        :label,
        :lane,
        :merge,
        :normal,
        :on,
        :output,
        :process,
        :processor,
        :producer,
        :publishes,
        :queue,
        :rate,
        :reads,
        :retry,
        :routes,
        :sends,
        :sink,
        :source,
        :split,
        :stage,
        :topic,
        :transform,
        :type,
        :weight,
        :writes
      ] do
    def unquote(verb)(_arg1 \\ nil, _arg2 \\ nil, _opts \\ []) do
      raise "DSL constructor `#{unquote(verb)}` must be called inside a DSL block"
    end
  end
end
