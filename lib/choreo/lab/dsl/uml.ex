defmodule Choreo.Lab.DSL.UML do
  import Choreo.Lab.DSL.Compiler

  @moduledoc """
  Experimental Livebook-friendly DSL for sketching UML class diagrams.

  This Lab DSL compiles to the stable, pipe-first `Choreo.UML` builders and
  returns an ordinary `%Choreo.UML{}`. Classes, structs, behaviors, protocols,
  and interfaces can be declared with block-based fields and functions. Edges
  expose UML relationship types as readable domain vocabulary.

  ## Examples

      iex> import Choreo.Lab.DSL.UML
      ...> diagram = uml do
      ...>   user = struct("User") do
      ...>     field :id, :integer
      ...>     private field(:email, :string)
      ...>     function :authenticate, 2, return: :boolean
      ...>   end
      ...>
      ...>   auth = behavior("AuthProvider") do
      ...>     function :verify, 1, return: :ok_error
      ...>   end
      ...>
      ...>   realizes user ~> auth, "implements"
      ...> end
      iex> diagram.graph.nodes[:user].type
      :struct
      iex> diagram.graph.nodes[:user].fields |> Enum.map(& &1[:name])
      ["id", "email"]
      iex> [meta] = Map.values(diagram.edge_meta)
      iex> {meta.type, meta.label}
      {:realizes, "implements"}

  Relationship edges can use typed constructors, generic `edge`, or pipe
  modifiers:

      inherits child ~> parent, "extends"
      realizes adapter ~> protocol, "implements"
      associates user ~> profile, "has one"
      depends controller ~> repo, "calls"
      edge controller ~> repo, depends: "calls"
      controller ~> repo |> depends("calls")

  The generic `~>` form defaults to `:depends`, which matches a lightweight
  dependency sketch.
  """

  @type class_decl :: %{id: Yog.node_id(), opts: keyword()}
  @type relationship_decl :: %{from: Yog.node_id(), to: Yog.node_id(), opts: keyword()}

  @node_verbs [:class, :struct, :behavior, :protocol, :interface]
  @member_verbs [
    :field,
    :attribute,
    :attr,
    :function,
    :method,
    :operation,
    :private,
    :protected,
    :public
  ]

  @relationship_verbs [
    :inherits,
    :extends,
    :realizes,
    :implements,
    :associates,
    :association,
    :has,
    :depends,
    :dependency,
    :uses
  ]

  @node_types %{
    class: :class,
    struct: :struct,
    behavior: :behavior,
    protocol: :protocol,
    interface: :interface
  }

  @relationship_aliases %{
    inherits: :inherits,
    extends: :inherits,
    realizes: :realizes,
    implements: :realizes,
    associates: :associates,
    association: :associates,
    has: :associates,
    depends: :depends,
    dependency: :depends,
    uses: :depends
  }

  @doc """
  Returns the vocabulary supported by the UML DSL.

  This is meant as a lightweight Livebook discovery helper when autocomplete is
  not enough.

      iex> taxonomy = Choreo.Lab.DSL.UML.taxonomy()
      iex> :struct in taxonomy.nodes
      true
      iex> :function in taxonomy.members
      true
      iex> :implements in taxonomy.edges
      true
  """
  @spec taxonomy() :: %{
          nodes: [atom()],
          members: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def taxonomy do
    %{
      nodes: @node_verbs,
      members: @member_verbs,
      edges: [:~>, :edge | @relationship_verbs],
      modifiers: [:on, :label | @relationship_verbs],
      options: [:label, :with, :id, :type, :arity, :return, :visibility | @relationship_verbs]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: %{
          nodes: [atom()],
          members: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.UML{}` from a compact Lab DSL block.
  """
  defmacro uml(do: block) do
    compile(block)
  end

  defmacro uml(opts, do: block) do
    compile(block, opts)
  end

  defp compile(block, opts \\ []) do
    {steps_reversed, _env} =
      block
      |> statements()
      |> Enum.reduce({[], %{}}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {Enum.reverse(statement_steps, steps), env}
      end)

    Enum.reduce(
      Enum.reverse(steps_reversed),
      quote(do: Choreo.UML.new(unquote(Macro.escape(opts)))),
      &pipe_step/2
    )
  end

  defp statement_steps({:=, meta, [{var, _, context}, constructor]}, env)
       when is_atom(var) and is_atom(context) do
    class = class_from_constructor(constructor, var, meta)
    {[{:class, class}], Map.put(env, var, class.id)}
  end

  defp statement_steps({:edge, meta, [edge_ast, label]}, env) when is_binary(label) do
    {relationship, classes} = relationship_from_ast(edge_ast, [label: label], env, meta)
    {relationship_declaration_steps(classes, relationship), env}
  end

  defp statement_steps({:edge, meta, [edge_ast, opts]}, env) when is_list(opts) do
    {relationship, classes} =
      relationship_from_ast(edge_ast, normalize_relationship_opts(opts), env, meta)

    {relationship_declaration_steps(classes, relationship), env}
  end

  defp statement_steps({:edge, meta, [edge_ast]}, env) do
    {relationship, classes} = relationship_from_ast(edge_ast, [], env, meta)
    {relationship_declaration_steps(classes, relationship), env}
  end

  for relationship <- @relationship_verbs do
    defp statement_steps({unquote(relationship), meta, [edge_ast, label, opts]}, env)
         when is_binary(label) and is_list(opts) do
      typed_relationship_statement(
        unquote(relationship),
        edge_ast,
        [label: label] ++ opts,
        env,
        meta
      )
    end

    defp statement_steps({unquote(relationship), meta, [edge_ast, label]}, env)
         when is_binary(label) do
      typed_relationship_statement(unquote(relationship), edge_ast, [label: label], env, meta)
    end

    defp statement_steps({unquote(relationship), meta, [edge_ast, opts]}, env)
         when is_list(opts) do
      typed_relationship_statement(unquote(relationship), edge_ast, opts, env, meta)
    end

    defp statement_steps({unquote(relationship), meta, [edge_ast]}, env) do
      typed_relationship_statement(unquote(relationship), edge_ast, [], env, meta)
    end
  end

  defp statement_steps({:|>, _meta, _args} = ast, env) do
    {relationship, classes} = relationship_from_piped_ast(ast, env)
    {relationship_declaration_steps(classes, relationship), env}
  end

  defp statement_steps({:~>, meta, _args} = ast, env) do
    {relationship, classes} = relationship_from_ast(ast, [], env, meta)
    {relationship_declaration_steps(classes, relationship), env}
  end

  defp statement_steps({name, meta, args} = ast, env) when is_atom(name) and is_list(args) do
    if class_constructor?(ast) do
      class = class_from_constructor(ast, nil, meta)
      {[{:class, class}], env}
    else
      unsupported_statement!(ast, meta)
    end
  end

  defp statement_steps(other, _env), do: unsupported_statement!(other, nil)

  defp typed_relationship_statement(name, edge_ast, opts, env, meta) do
    opts = opts |> normalize_relationship_opts() |> Keyword.put(:type, relationship_type!(name))
    {relationship, classes} = relationship_from_ast(edge_ast, opts, env, meta)
    {relationship_declaration_steps(classes, relationship), env}
  end

  defp relationship_declaration_steps(classes, relationship) do
    classes
    |> Enum.reduce([{:relationship, relationship}], fn class, steps ->
      [{:class, class} | steps]
    end)
    |> Enum.reverse()
  end

  defp relationship_from_piped_ast(ast, env) do
    {base, modifiers} = unwrap_pipe(ast, [])
    opts = modifiers |> Enum.reduce([], &modifier_opt/2) |> normalize_relationship_opts()
    relationship_from_ast(base, opts, env, line_meta(base))
  end

  defp modifier_opt({name, _meta, [value]}, acc) when name in [:on, :label] do
    Keyword.put(acc, :label, value)
  end

  defp modifier_opt({name, _meta, []}, acc) do
    if relationship_name?(name) do
      Keyword.put(acc, :type, relationship_type!(name))
    else
      unsupported_modifier!(name, [])
    end
  end

  defp modifier_opt({name, _meta, [label]}, acc) when is_binary(label) do
    if relationship_name?(name) do
      acc
      |> Keyword.put(:type, relationship_type!(name))
      |> Keyword.put(:label, label)
    else
      unsupported_modifier!(name, [label])
    end
  end

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported UML relationship modifier: #{Macro.to_string(other)}; " <>
            "use `on(value)`, `label(value)`, `depends(value)`, or `implements(value)`"
  end

  defp unsupported_modifier!(name, args) do
    rendered = Macro.to_string({name, [], args})

    raise ArgumentError,
          "unsupported UML relationship modifier: #{rendered}; " <>
            "use `on(value)`, `label(value)`, `depends(value)`, or `implements(value)`"
  end

  defp relationship_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, from_class} = endpoint_id(from_ast, env, meta)
    {to, to_class} = endpoint_id(to_ast, env, meta)
    classes = [from_class, to_class] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)
    opts = opts |> normalize_relationship_opts() |> Keyword.put_new(:type, :depends)

    {%{from: from, to: to, opts: opts}, classes}
  end

  defp relationship_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in UML DSL, got #{Macro.to_string(other)}" <> line_suffix(meta)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env, var) do
      {:ok, id} -> {id, nil}
      :error -> raise ArgumentError, "unknown UML class variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, _env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if class_constructor?(constructor) do
      class = class_from_constructor(constructor, nil, meta)
      {class.id, class}
    else
      raise ArgumentError, "unknown UML class constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported UML relationship endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a class first, e.g. `user = struct(\"User\") do ... end`"
  end

  defp class_from_constructor({name, meta, args}, var, _statement_meta)
       when is_map_key(@node_types, name) and is_list(args) do
    {block, args} = pop_do_block(args)
    {opts, positional} = pop_trailing_opts(args)
    {id, opts} = class_id_and_opts(var, positional, opts, meta)
    {fields, functions} = members_from_block(block)

    opts =
      opts
      |> Keyword.put(:type, @node_types[name])
      |> Keyword.put_new(:fields, fields)
      |> Keyword.put_new(:functions, functions)

    %{id: id, opts: opts}
  end

  defp class_from_constructor(other, _var, meta) do
    raise ArgumentError,
          "expected UML class constructor, got #{Macro.to_string(other)}#{line_suffix(meta)}"
  end

  defp class_constructor?({name, _meta, args})
       when is_map_key(@node_types, name) and is_list(args), do: true

  defp class_constructor?(_other), do: false

  defp class_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "UML class constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline UML class constructors need a label/id or `id:` option#{line_suffix(meta)}"
    end
  end

  defp members_from_block(nil), do: {[], []}

  defp members_from_block(block) do
    {fields, functions} =
      block
      |> statements()
      |> Enum.reduce({[], []}, fn statement, {fields, functions} ->
        case member_from_ast(statement) do
          {:field, field} -> {[field | fields], functions}
          {:function, function} -> {fields, [function | functions]}
        end
      end)

    {Enum.reverse(fields), Enum.reverse(functions)}
  end

  defp member_from_ast({visibility, _meta, [inner]})
       when visibility in [:private, :protected, :public] do
    {kind, member} = member_from_ast(inner)
    {kind, Map.put(member, :visibility, visibility)}
  end

  defp member_from_ast({name, meta, args}) when name in [:field, :attribute, :attr] do
    {opts, positional} = pop_trailing_opts(args)
    {:field, member_from_parts(:field, positional, opts, meta)}
  end

  defp member_from_ast({name, meta, args}) when name in [:function, :method, :operation] do
    {opts, positional} = pop_trailing_opts(args)
    {:function, member_from_parts(:function, positional, opts, meta)}
  end

  defp member_from_ast(other) do
    raise ArgumentError,
          "unsupported member declaration in UML DSL: #{Macro.to_string(other)}; " <>
            "use `field name, type`, `function name, arity`, or visibility wrappers like `private field(...)`"
  end

  defp member_from_parts(:field, [name], opts, _meta) do
    opts
    |> Keyword.put(:name, name)
    |> Map.new()
  end

  defp member_from_parts(:field, [name, type], opts, _meta) do
    opts
    |> Keyword.put(:name, name)
    |> Keyword.put_new(:type, type)
    |> Map.new()
  end

  defp member_from_parts(:field, _positional, _opts, meta) do
    raise ArgumentError,
          "UML field declarations require name and optional type#{line_suffix(meta)}"
  end

  defp member_from_parts(:function, [name], opts, _meta) do
    opts
    |> Keyword.put(:name, name)
    |> Map.new()
  end

  defp member_from_parts(:function, [name, arity], opts, _meta) do
    opts
    |> Keyword.put(:name, name)
    |> Keyword.put_new(:arity, arity)
    |> Map.new()
  end

  defp member_from_parts(:function, _positional, _opts, meta) do
    raise ArgumentError,
          "UML function declarations require name and optional arity#{line_suffix(meta)}"
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
          "inline UML class label/id must be a string or atom, got #{inspect(other)}"
  end

  defp normalize_relationship_opts(opts) do
    opts
    |> normalize_label_alias(:with)
    |> normalize_relationship_aliases()
  end

  defp normalize_label_alias(opts, key) do
    {value, opts} = Keyword.pop(opts, key)
    if value == nil, do: opts, else: Keyword.put_new(opts, :label, value)
  end

  defp normalize_relationship_aliases(opts) do
    Enum.reduce(@relationship_aliases, opts, fn {key, type}, acc ->
      {value, acc} = Keyword.pop(acc, key)

      if value == nil do
        acc
      else
        acc
        |> Keyword.put_new(:type, type)
        |> Keyword.put_new(:label, value)
      end
    end)
  end

  defp relationship_name?(name), do: Map.has_key?(@relationship_aliases, name)
  defp relationship_type!(name), do: Map.fetch!(@relationship_aliases, name)

  defp pipe_step({:class, %{id: id, opts: opts}}, acc) do
    quote do
      Choreo.UML.add_class(
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp pipe_step({:relationship, %{from: from, to: to, opts: opts}}, acc) do
    quote do
      Choreo.UML.add_relationship(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in UML DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
  end

  # Autocomplete helper stubs
  for verb <- [
        :associates,
        :association,
        :attr,
        :attribute,
        :behavior,
        :class,
        :dependency,
        :depends,
        :extends,
        :field,
        :function,
        :has,
        :implements,
        :inherits,
        :interface,
        :method,
        :operation,
        :private,
        :protected,
        :protocol,
        :public,
        :realizes,
        :struct,
        :uses
      ] do
    def unquote(verb)(_arg1 \\ nil, _arg2 \\ nil, _opts \\ []) do
      raise "DSL constructor `#{unquote(verb)}` must be called inside a DSL block"
    end
  end
end
