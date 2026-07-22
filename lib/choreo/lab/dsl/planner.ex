defmodule Choreo.Lab.DSL.Planner do
  @moduledoc """
  Experimental Livebook-friendly DSL for sketching project plans.

  This Lab DSL compiles to the stable, pipe-first `Choreo.Planner` builders and
  returns an ordinary `%Choreo.Planner{}`. It is useful for interview planning,
  release sketches, dependency conversations, and quick Kanban/Gantt artifacts.

  ## Examples

      iex> import Choreo.Lab.DSL.Planner
      ...> plan = planner "Launch v1" do
      ...>   v1 = milestone("V1 Launch")
      ...>   design = task("Design API", status: :done, estimate_hours: 8)
      ...>   build = task("Build Gateway", priority: :high)
      ...>   alice = user("Alice")
      ...>   backend = label("backend")
      ...>
      ...>   contains v1 ~> design
      ...>   contains v1 ~> build
      ...>   design ~> build |> depends_on()
      ...>   build ~> alice |> assigned_to()
      ...>   build ~> backend |> tagged_with()
      ...> end
      iex> Enum.sort(Choreo.Planner.children(plan, :v1))
      [:build, :design]
      iex> Choreo.Planner.dependencies(plan, :build)
      [:design]
      iex> Choreo.Planner.assignee(plan, :build)
      :alice

  Edges use the same sketch grammar as the other Lab DSLs:

      design ~> build
      design ~> build |> depends_on("finish design first")
      blocks blocker ~> blocked
      contains milestone ~> task
      assigned_to task ~> user
      tagged_with task ~> label

  Planner edge labels are accepted for grammar consistency, but the stable
  `Choreo.Planner` model currently stores typed relationships rather than
  display labels on those edges.
  """

  @node_verbs [
    :task,
    :todo,
    :story,
    :bug,
    :work,
    :milestone,
    :release,
    :phase,
    :user,
    :person,
    :owner,
    :label,
    :tag
  ]

  @node_builders %{
    task: :add_task,
    todo: :add_task,
    story: :add_task,
    bug: :add_task,
    work: :add_task,
    milestone: :add_milestone,
    release: :add_milestone,
    phase: :add_milestone,
    user: :add_user,
    person: :add_user,
    owner: :add_user,
    label: :add_label,
    tag: :add_label
  }

  @edge_verbs [
    :depends_on,
    :depends,
    :after,
    :blocks,
    :contains,
    :assigned_to,
    :assign,
    :tagged_with,
    :tagged,
    :relates_to,
    :relates
  ]

  @edge_type_aliases %{
    depends_on: :depends_on,
    depends: :depends_on,
    after: :depends_on,
    blocks: :blocks,
    contains: :contains,
    assigned_to: :assigned_to,
    assign: :assigned_to,
    tagged_with: :tagged_with,
    tagged: :tagged_with,
    relates_to: :relates_to,
    relates: :relates_to
  }

  @doc """
  Returns the vocabulary supported by the planner DSL.

      iex> taxonomy = Choreo.Lab.DSL.Planner.taxonomy()
      iex> :task in taxonomy.nodes
      true
      iex> :depends_on in taxonomy.edges
      true
      iex> :assigned_to in taxonomy.modifiers
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
      edges: [:~>, :edge | @edge_verbs],
      modifiers: [:on, :label | @edge_verbs],
      options: [
        :id,
        :title,
        :with,
        :status,
        :priority,
        :due_date,
        :estimate_hours,
        :actual_hours,
        :email,
        :type | @edge_verbs
      ]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: map()
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.Planner{}` from a compact Lab DSL block.
  """
  defmacro planner(do: block), do: compile(block)
  defmacro planner(name_or_opts, do: block), do: compile(block, name_or_opts)

  defp compile(block, name_or_opts \\ []) do
    {steps, _env} =
      block
      |> statements()
      |> Enum.reduce({[], empty_env()}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {steps ++ statement_steps, env}
      end)

    Enum.reduce(
      steps,
      quote(do: Choreo.Planner.new(unquote(Macro.escape(name_or_opts)))),
      &pipe_step/2
    )
  end

  defp statements({:__block__, _meta, list}), do: list
  defp statements(nil), do: []
  defp statements(single), do: [single]

  defp empty_env, do: %{nodes: %{}}

  defp statement_steps({:=, meta, [{var, _, context}, constructor]}, env)
       when is_atom(var) and is_atom(context) do
    if node_constructor?(constructor) do
      node = node_from_constructor(constructor, var, meta)
      {[{:node, node}], put_in(env.nodes[var], node.id)}
    else
      raise ArgumentError,
            "expected planner constructor, got #{Macro.to_string(constructor)}#{line_suffix(meta)}"
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

  defp typed_edge_args!(_name, [edge_ast, opts], _meta) when is_list(opts), do: {edge_ast, opts}
  defp typed_edge_args!(_name, [edge_ast], _meta), do: {edge_ast, []}

  defp typed_edge_args!(name, args, meta) do
    raise ArgumentError,
          "unsupported planner edge form `#{name}/#{length(args)}`#{line_suffix(meta)}; " <>
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

  defp modifier_opt({name, _meta, []}, acc) when name in @edge_verbs,
    do: edge_type_opts(acc, name)

  defp modifier_opt({name, _meta, [value]}, acc) when name in @edge_verbs do
    acc
    |> edge_type_opts(name)
    |> Keyword.put_new(:label, value)
  end

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported planner edge modifier: #{Macro.to_string(other)}; " <>
            "use `depends_on()`, `blocks()`, `contains()`, `assigned_to()`, or `tagged_with()`"
  end

  defp edge_from_ast({:~>, meta, endpoints}, opts, env, _statement_meta) do
    endpoints
    |> Enum.map(&endpoint_id(&1, env, meta))
    |> edge_from_endpoint_pairs(opts)
  end

  defp edge_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in planner DSL, got #{Macro.to_string(other)}#{line_suffix(meta)}"
  end

  defp edge_from_endpoint_pairs([{from, from_node}, {to, to_node}], opts) do
    declared_nodes = [from_node, to_node] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)
    {%{from: from, to: to, opts: normalize_edge_opts(opts)}, declared_nodes}
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env.nodes, var) do
      {:ok, id} -> {id, nil}
      :error -> raise ArgumentError, "unknown planner node variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, _env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@node_builders, name) do
      node = node_from_constructor(constructor, nil, meta)
      {node.id, node}
    else
      raise ArgumentError, "unknown planner node constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported planner edge endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a node first, e.g. `build = task(\"Build\")`"
  end

  defp node_from_constructor({name, meta, args}, var, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@node_builders, name) ||
        raise ArgumentError, "unknown planner node constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    {id, opts} = node_id_and_opts(var, positional, opts, meta)
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
              "planner node constructors take at most one positional title/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_title(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_title(opts, List.first(positional))}

      positional != [] ->
        title_or_id = List.first(positional)
        {id_from_title(title_or_id), maybe_put_title(opts, title_or_id)}

      true ->
        raise ArgumentError,
              "inline planner node constructors need a title/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp maybe_put_title(opts, nil), do: opts

  defp maybe_put_title(opts, title) when is_binary(title),
    do: Keyword.put_new(opts, :title, title)

  defp maybe_put_title(opts, title) when is_atom(title),
    do: Keyword.put_new(opts, :title, to_string(title))

  defp maybe_put_title(opts, _other), do: opts

  defp id_from_title(id) when is_atom(id), do: id
  defp id_from_title(id) when is_binary(id), do: slug_atom(id)

  defp id_from_title(other) do
    raise ArgumentError,
          "inline planner node title/id must be a string or atom, got #{inspect(other)}"
  end

  defp slug_atom(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> raise ArgumentError, "cannot derive a planner node id from an empty title"
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
    Keyword.put(opts, :type, Map.fetch!(@edge_type_aliases, name))
  end

  defp node_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(@node_builders, name)

  defp node_constructor?(_other), do: false

  defp pipe_step({:node, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.Planner, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:edge, %{from: from, to: to, opts: opts}}, acc) do
    case Keyword.get(opts, :type, :depends_on) do
      :contains ->
        quote do
          Choreo.Planner.contains(
            unquote(acc),
            unquote(Macro.escape(from)),
            unquote(Macro.escape(to))
          )
        end

      :depends_on ->
        quote do
          Choreo.Planner.depends_on(
            unquote(acc),
            unquote(Macro.escape(to)),
            unquote(Macro.escape(from))
          )
        end

      :blocks ->
        quote do
          Choreo.Planner.blocks(
            unquote(acc),
            unquote(Macro.escape(from)),
            unquote(Macro.escape(to))
          )
        end

      :assigned_to ->
        quote do
          Choreo.Planner.assign(
            unquote(acc),
            unquote(Macro.escape(from)),
            unquote(Macro.escape(to))
          )
        end

      :tagged_with ->
        quote do
          Choreo.Planner.tag(unquote(acc), unquote(Macro.escape(from)), unquote(Macro.escape(to)))
        end

      :relates_to ->
        quote do
          Choreo.Planner.relates(
            unquote(acc),
            unquote(Macro.escape(from)),
            unquote(Macro.escape(to))
          )
        end
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in planner DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
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
