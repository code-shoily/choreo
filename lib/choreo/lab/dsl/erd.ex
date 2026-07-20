defmodule Choreo.Lab.DSL.ERD do
  @moduledoc """
  Experimental Livebook-friendly DSL for sketching entity-relationship diagrams.

  This Lab DSL compiles to the stable, pipe-first `Choreo.ERD` builders and
  returns an ordinary `%Choreo.ERD{}`. Tables can be declared as compact column
  blocks, while relationship edges expose ERD cardinalities as domain vocabulary.

  ## Examples

      iex> import Choreo.Lab.DSL.ERD
      ...> schema = erd do
      ...>   users = table("users") do
      ...>     pk :id, :integer
      ...>     field :email, :varchar, comment: "unique email"
      ...>   end
      ...>
      ...>   posts = table("posts") do
      ...>     pk :id, :integer
      ...>     fk :user_id, :integer
      ...>     field :title, :varchar
      ...>   end
      ...>
      ...>   one_to_many users ~> posts, "writes", from: :id, to: :user_id
      ...> end
      iex> schema.graph.nodes[:users].columns |> Enum.map(& &1[:name])
      [:id, :email]
      iex> [meta] = Map.values(schema.edge_meta)
      iex> {meta.cardinality, meta.label, meta.from_column, meta.to_column}
      {:one_to_many, "writes", :id, :user_id}

  Relationship edges can use typed constructors, generic `edge`, or pipe
  modifiers:

      one_to_many users ~> posts, "writes"
      has_many users ~> posts, "writes"
      edge users ~> posts, one_to_many: "writes"
      users ~> posts |> one_to_many("writes") |> columns(:id, :user_id)

  The generic `~>` form defaults to `:one_to_many`, which matches the most common
  parent-table-to-child-table sketching direction.
  """

  @type table_decl :: %{id: Yog.node_id(), opts: keyword()}
  @type relationship_decl :: %{from: Yog.node_id(), to: Yog.node_id(), opts: keyword()}

  @table_verbs [:table, :entity]
  @column_verbs [:field, :column, :pk, :primary_key, :fk, :foreign_key]

  @cardinality_verbs [
    :one_to_one,
    :one_to_many,
    :zero_or_one_to_many,
    :exactly_one_to_many,
    :many_to_many,
    :has_one,
    :has_many,
    :maybe_has_many,
    :has_at_least_one,
    :has_and_belongs_to_many
  ]

  @cardinality_aliases %{
    one_to_one: :one_to_one,
    one_to_many: :one_to_many,
    zero_or_one_to_many: :zero_or_one_to_many,
    exactly_one_to_many: :exactly_one_to_many,
    many_to_many: :many_to_many,
    has_one: :one_to_one,
    has_many: :one_to_many,
    maybe_has_many: :zero_or_one_to_many,
    has_at_least_one: :exactly_one_to_many,
    has_and_belongs_to_many: :many_to_many
  }

  @doc """
  Returns the vocabulary supported by the ERD DSL.

  This is meant as a lightweight Livebook discovery helper when autocomplete is
  not enough.

      iex> taxonomy = Choreo.Lab.DSL.ERD.taxonomy()
      iex> :table in taxonomy.tables
      true
      iex> :pk in taxonomy.columns
      true
      iex> :one_to_many in taxonomy.edges
      true
  """
  @spec taxonomy() :: %{
          tables: [atom()],
          columns: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def taxonomy do
    %{
      tables: @table_verbs,
      columns: @column_verbs,
      edges: [:~>, :edge | @cardinality_verbs],
      modifiers: [:on, :label, :columns, :from, :to | @cardinality_verbs],
      options: [
        :label,
        :with,
        :id,
        :cardinality,
        :from,
        :to,
        :from_column,
        :to_column | @cardinality_verbs
      ]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: %{
          tables: [atom()],
          columns: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.ERD{}` from a compact Lab DSL block.
  """
  defmacro erd(do: block) do
    compile(block)
  end

  defmacro erd(opts, do: block) do
    compile(block, opts)
  end

  defp compile(block, opts \\ []) do
    {steps, _env} =
      block
      |> statements()
      |> Enum.reduce({[], %{}}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {steps ++ statement_steps, env}
      end)

    Enum.reduce(steps, quote(do: Choreo.ERD.new(unquote(Macro.escape(opts)))), &pipe_step/2)
  end

  defp statements({:__block__, _meta, list}), do: list
  defp statements(nil), do: []
  defp statements(single), do: [single]

  defp statement_steps({:=, meta, [{var, _, context}, constructor]}, env)
       when is_atom(var) and is_atom(context) do
    table = table_from_constructor(constructor, var, meta)
    {[{:table, table}], Map.put(env, var, table.id)}
  end

  defp statement_steps({:edge, meta, [edge_ast, label]}, env) when is_binary(label) do
    {relationship, tables} = relationship_from_ast(edge_ast, [label: label], env, meta)
    {relationship_declaration_steps(tables, relationship), env}
  end

  defp statement_steps({:edge, meta, [edge_ast, opts]}, env) when is_list(opts) do
    {relationship, tables} =
      relationship_from_ast(edge_ast, normalize_relationship_opts(opts), env, meta)

    {relationship_declaration_steps(tables, relationship), env}
  end

  defp statement_steps({:edge, meta, [edge_ast]}, env) do
    {relationship, tables} = relationship_from_ast(edge_ast, [], env, meta)
    {relationship_declaration_steps(tables, relationship), env}
  end

  defp statement_steps({name, meta, [edge_ast, label, opts]}, env)
       when name in [
              :one_to_one,
              :one_to_many,
              :zero_or_one_to_many,
              :exactly_one_to_many,
              :many_to_many,
              :has_one,
              :has_many,
              :maybe_has_many,
              :has_at_least_one,
              :has_and_belongs_to_many
            ] and is_binary(label) and is_list(opts) do
    typed_relationship_statement(name, edge_ast, [label: label] ++ opts, env, meta)
  end

  defp statement_steps({name, meta, [edge_ast, label]}, env)
       when name in [
              :one_to_one,
              :one_to_many,
              :zero_or_one_to_many,
              :exactly_one_to_many,
              :many_to_many,
              :has_one,
              :has_many,
              :maybe_has_many,
              :has_at_least_one,
              :has_and_belongs_to_many
            ] and is_binary(label) do
    typed_relationship_statement(name, edge_ast, [label: label], env, meta)
  end

  defp statement_steps({name, meta, [edge_ast, opts]}, env)
       when name in [
              :one_to_one,
              :one_to_many,
              :zero_or_one_to_many,
              :exactly_one_to_many,
              :many_to_many,
              :has_one,
              :has_many,
              :maybe_has_many,
              :has_at_least_one,
              :has_and_belongs_to_many
            ] and is_list(opts) do
    typed_relationship_statement(name, edge_ast, opts, env, meta)
  end

  defp statement_steps({name, meta, [edge_ast]}, env)
       when name in [
              :one_to_one,
              :one_to_many,
              :zero_or_one_to_many,
              :exactly_one_to_many,
              :many_to_many,
              :has_one,
              :has_many,
              :maybe_has_many,
              :has_at_least_one,
              :has_and_belongs_to_many
            ] do
    typed_relationship_statement(name, edge_ast, [], env, meta)
  end

  defp statement_steps({:|>, _meta, _args} = ast, env) do
    {relationship, tables} = relationship_from_piped_ast(ast, env)
    {relationship_declaration_steps(tables, relationship), env}
  end

  defp statement_steps({:~>, meta, _args} = ast, env) do
    {relationship, tables} = relationship_from_ast(ast, [], env, meta)
    {relationship_declaration_steps(tables, relationship), env}
  end

  defp statement_steps({name, meta, args} = ast, env) when is_atom(name) and is_list(args) do
    if table_constructor?(ast) do
      table = table_from_constructor(ast, nil, meta)
      {[{:table, table}], env}
    else
      unsupported_statement!(ast, meta)
    end
  end

  defp statement_steps(other, _env), do: unsupported_statement!(other, nil)

  defp typed_relationship_statement(name, edge_ast, opts, env, meta) do
    case cardinality_for(name) do
      {:ok, cardinality} ->
        opts = opts |> normalize_relationship_opts() |> Keyword.put(:cardinality, cardinality)
        {relationship, tables} = relationship_from_ast(edge_ast, opts, env, meta)
        {relationship_declaration_steps(tables, relationship), env}

      :error ->
        unsupported_statement!({name, meta, [edge_ast | List.wrap(opts)]}, meta)
    end
  end

  defp relationship_declaration_steps(tables, relationship) do
    tables
    |> Enum.reduce([{:relationship, relationship}], fn table, steps ->
      [{:table, table} | steps]
    end)
    |> Enum.reverse()
  end

  defp relationship_from_piped_ast(ast, env) do
    {base, modifiers} = unwrap_pipe(ast, [])
    opts = modifiers |> Enum.reduce([], &modifier_opt/2) |> normalize_relationship_opts()
    relationship_from_ast(base, opts, env, line_meta(base))
  end

  defp unwrap_pipe({:|>, _meta, [left, right]}, acc), do: unwrap_pipe(left, [right | acc])
  defp unwrap_pipe(base, acc), do: {base, acc}

  defp modifier_opt({name, _meta, [value]}, acc) when name in [:on, :label] do
    Keyword.put(acc, :label, value)
  end

  defp modifier_opt({:from, _meta, [value]}, acc), do: Keyword.put(acc, :from_column, value)
  defp modifier_opt({:to, _meta, [value]}, acc), do: Keyword.put(acc, :to_column, value)

  defp modifier_opt({:columns, _meta, [from_column, to_column]}, acc) do
    acc
    |> Keyword.put(:from_column, from_column)
    |> Keyword.put(:to_column, to_column)
  end

  defp modifier_opt({name, _meta, []}, acc) do
    case cardinality_for(name) do
      {:ok, cardinality} -> Keyword.put(acc, :cardinality, cardinality)
      :error -> unsupported_modifier!(name, [])
    end
  end

  defp modifier_opt({name, _meta, [label]}, acc) when is_binary(label) do
    case cardinality_for(name) do
      {:ok, cardinality} ->
        acc
        |> Keyword.put(:cardinality, cardinality)
        |> Keyword.put(:label, label)

      :error ->
        unsupported_modifier!(name, [label])
    end
  end

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported ERD relationship modifier: #{Macro.to_string(other)}; " <>
            "use `on(value)`, `label(value)`, `one_to_many(value)`, or `columns(from, to)`"
  end

  defp unsupported_modifier!(name, args) do
    rendered = Macro.to_string({name, [], args})

    raise ArgumentError,
          "unsupported ERD relationship modifier: #{rendered}; " <>
            "use `on(value)`, `label(value)`, `one_to_many(value)`, or `columns(from, to)`"
  end

  defp relationship_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, from_table} = endpoint_id(from_ast, env, meta)
    {to, to_table} = endpoint_id(to_ast, env, meta)
    tables = [from_table, to_table] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)
    opts = opts |> normalize_relationship_opts() |> Keyword.put_new(:cardinality, :one_to_many)

    {%{from: from, to: to, opts: opts}, tables}
  end

  defp relationship_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in ERD DSL, got #{Macro.to_string(other)}" <> line_suffix(meta)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env, var) do
      {:ok, id} -> {id, nil}
      :error -> raise ArgumentError, "unknown ERD table variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, _env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if table_constructor?(constructor) do
      table = table_from_constructor(constructor, nil, meta)
      {table.id, table}
    else
      raise ArgumentError, "unknown ERD table constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported ERD relationship endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a table first, e.g. `users = table(\"users\") do ... end`"
  end

  defp table_from_constructor({name, meta, args}, var, _statement_meta)
       when name in [:table, :entity] and is_list(args) do
    {block, args} = pop_do_block(args)
    {opts, positional} = pop_trailing_opts(args)
    {id, opts} = table_id_and_opts(var, positional, opts, meta)
    columns = columns_from_block(block)
    opts = Keyword.put_new(opts, :columns, columns)
    %{id: id, opts: opts}
  end

  defp table_from_constructor(other, _var, meta) do
    raise ArgumentError,
          "expected ERD table constructor, got #{Macro.to_string(other)}#{line_suffix(meta)}"
  end

  defp table_constructor?({name, _meta, args}) when name in [:table, :entity] and is_list(args),
    do: true

  defp table_constructor?(_other), do: false

  defp pop_do_block(args) do
    case List.last(args) do
      [do: block] -> {block, Enum.drop(args, -1)}
      _other -> {nil, args}
    end
  end

  defp pop_trailing_opts(args) do
    case List.last(args) do
      last when is_list(last) ->
        if Keyword.keyword?(last), do: {last, Enum.drop(args, -1)}, else: {[], args}

      _other ->
        {[], args}
    end
  end

  defp table_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "ERD table constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline ERD table constructors need a label/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp columns_from_block(nil), do: []

  defp columns_from_block(block) do
    block
    |> statements()
    |> Enum.map(&column_from_ast/1)
  end

  defp column_from_ast({name, meta, args})
       when name in [:field, :column, :pk, :primary_key, :fk, :foreign_key] do
    {opts, positional} = pop_trailing_opts(args)
    column_kind = column_kind(name)
    column_from_parts(column_kind, positional, opts, meta)
  end

  defp column_from_ast(other) do
    raise ArgumentError,
          "unsupported column declaration in ERD DSL: #{Macro.to_string(other)}; " <>
            "use `field name, type`, `pk name, type`, or `fk name, type`"
  end

  defp column_from_parts(key, positional, opts, meta) do
    cond do
      length(positional) != 2 ->
        raise ArgumentError,
              "ERD column declarations require name and type#{line_suffix(meta)}"

      key == nil ->
        opts

      true ->
        Keyword.put_new(opts, :key, key)
    end
    |> Keyword.put(:name, Enum.at(positional, 0))
    |> Keyword.put(:type, Enum.at(positional, 1))
    |> Map.new()
  end

  defp column_kind(name) when name in [:pk, :primary_key], do: :pk
  defp column_kind(name) when name in [:fk, :foreign_key], do: :fk
  defp column_kind(_name), do: nil

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
          "inline ERD table label/id must be a string or atom, got #{inspect(other)}"
  end

  defp slug_atom(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> raise ArgumentError, "cannot derive an ERD table id from an empty label"
      slug -> String.to_atom(slug)
    end
  end

  defp normalize_relationship_opts(opts) do
    opts
    |> normalize_column_alias(:from, :from_column)
    |> normalize_column_alias(:to, :to_column)
    |> normalize_label_alias(:with)
    |> normalize_cardinality_aliases()
  end

  defp normalize_column_alias(opts, from_key, to_key) do
    {value, opts} = Keyword.pop(opts, from_key)
    if value == nil, do: opts, else: Keyword.put_new(opts, to_key, value)
  end

  defp normalize_label_alias(opts, key) do
    {value, opts} = Keyword.pop(opts, key)
    if value == nil, do: opts, else: Keyword.put_new(opts, :label, value)
  end

  defp normalize_cardinality_aliases(opts) do
    Enum.reduce(@cardinality_aliases, opts, fn {key, cardinality}, acc ->
      {value, acc} = Keyword.pop(acc, key)

      if value == nil do
        acc
      else
        acc
        |> Keyword.put_new(:cardinality, cardinality)
        |> Keyword.put_new(:label, value)
      end
    end)
  end

  defp cardinality_for(name), do: Map.fetch(@cardinality_aliases, name)

  defp pipe_step({:table, %{id: id, opts: opts}}, acc) do
    quote do
      Choreo.ERD.add_table(
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp pipe_step({:relationship, %{from: from, to: to, opts: opts}}, acc) do
    quote do
      Choreo.ERD.add_relationship(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in ERD DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
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
