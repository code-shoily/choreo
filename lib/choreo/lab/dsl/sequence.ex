defmodule Choreo.Lab.DSL.Sequence do
  import Choreo.Lab.DSL.Compiler

  @moduledoc """
  Experimental Livebook-friendly DSL for sketching sequence diagrams.

  Unlike most Choreo Lab DSLs, sequence diagrams are primarily ordered event
  streams rather than static topology. This DSL still uses participant
  constructors for nouns, but message, activation, note, and fragment statements
  compile to ordered `Choreo.Sequence` events.

  ## Examples

      iex> import Choreo.Lab.DSL.Sequence
      ...> diagram = sequence do
      ...>   user = actor("User")
      ...>   api = participant("API")
      ...>   db = participant("Database")
      ...>
      ...>   user ~> api |> call("GET /accounts")
      ...>   activate api
      ...>   api ~> db |> call("SELECT accounts")
      ...>   reply db ~> api, "rows"
      ...>   deactivate api
      ...>   reply api ~> user, "200 OK"
      ...> end
      iex> Choreo.Sequence.participants(diagram)
      [:user, :api, :db]
      iex> Choreo.Sequence.messages(diagram) |> Enum.map(& &1[:label])
      ["GET /accounts", "SELECT accounts", "rows", "200 OK"]

  Message edges can use pipe modifiers, typed constructors, or generic `edge`:

      user ~> api |> call("GET /accounts")
      async api ~> worker, "enqueue job"
      reply db ~> api, "rows"
      edge api ~> db, async: "fire and forget"

  Notes and fragments are event statements:

      over api, "Validates bearer token"
      between api, db, "Tenant scoped query"

      loop "retry up to 3 times" do
        api ~> worker |> async("process job")
      end

      alt "authorized" do
        api ~> db |> call("read tenant")
        otherwise "denied"
        api ~> user |> reply("403")
      end
  """

  @type participant_decl :: %{id: atom(), builder: atom(), opts: keyword()}
  @type step ::
          {:participant, participant_decl()}
          | {:message, map()}
          | {:activation, atom(), atom()}
          | {:note, tuple(), String.t()}
          | {:fragment, atom(), String.t() | nil}
          | :end_fragment

  @participant_verbs [:actor, :participant, :service, :system, :user]

  @participant_builders %{
    actor: :add_actor,
    user: :add_actor,
    participant: :add_participant,
    service: :add_participant,
    system: :add_participant
  }

  @message_verbs [
    :message,
    :call,
    :request,
    :sync,
    :async,
    :signal,
    :publish,
    :reply,
    :return,
    :response
  ]

  @message_types %{
    message: :sync,
    call: :sync,
    request: :sync,
    sync: :sync,
    async: :async,
    signal: :async,
    publish: :async,
    reply: :return,
    return: :return,
    response: :return
  }

  @fragment_verbs [:loop, :opt, :alt, :otherwise, :else, :and, :par, :break, :critical]

  @doc """
  Returns the vocabulary supported by the sequence DSL.

  This is meant as a lightweight Livebook discovery helper when autocomplete is
  not enough.

      iex> taxonomy = Choreo.Lab.DSL.Sequence.taxonomy()
      iex> :actor in taxonomy.participants
      true
      iex> :reply in taxonomy.messages
      true
      iex> :loop in taxonomy.fragments
      true
  """
  @spec taxonomy() :: %{
          participants: [atom()],
          messages: [atom()],
          events: [atom()],
          notes: [atom()],
          fragments: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def taxonomy do
    %{
      participants: @participant_verbs,
      messages: [:~>, :edge | @message_verbs],
      events: [:activate, :deactivate],
      notes: [:note, :over, :left, :right, :between],
      fragments: @fragment_verbs,
      modifiers: [:on, :label | @message_verbs],
      options: [:label, :with, :id, :description, :type, :sync, :async, :reply, :return]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: map()
  def verbs, do: taxonomy()

  @doc """
  Builds a `%Choreo.Sequence{}` from a compact Lab DSL block.
  """
  defmacro sequence(do: block), do: compile(block)
  defmacro sequence(opts, do: block), do: compile(block, opts)

  defp compile(block, opts \\ []) do
    {steps, _env} = compile_statements(statements(block), %{})
    Enum.reduce(steps, quote(do: Choreo.Sequence.new(unquote(Macro.escape(opts)))), &pipe_step/2)
  end

  defp compile_statements(statements, env) do
    {steps_reversed, env} =
      Enum.reduce(statements, {[], env}, fn statement, {steps, env} ->
        {statement_steps, env} = statement_steps(statement, env)
        {Enum.reverse(statement_steps, steps), env}
      end)

    {Enum.reverse(steps_reversed), env}
  end

  defp statement_steps({:=, meta, [{var, _, context}, constructor]}, env)
       when is_atom(var) and is_atom(context) do
    participant = participant_from_constructor(constructor, var, meta)
    {[{:participant, participant}], Map.put(env, var, participant.id)}
  end

  defp statement_steps({:edge, meta, [edge_ast, label]}, env) when is_binary(label) do
    {message, participants} = message_from_ast(edge_ast, [label: label], env, meta)
    {message_declaration_steps(participants, message), env}
  end

  defp statement_steps({:edge, meta, [edge_ast, opts]}, env) when is_list(opts) do
    {message, participants} = message_from_ast(edge_ast, normalize_message_opts(opts), env, meta)
    {message_declaration_steps(participants, message), env}
  end

  defp statement_steps({:edge, meta, [edge_ast]}, env) do
    {message, participants} = message_from_ast(edge_ast, [], env, meta)
    {message_declaration_steps(participants, message), env}
  end

  for message_name <- @message_verbs do
    defp statement_steps({unquote(message_name), meta, [edge_ast, label, opts]}, env)
         when is_binary(label) and is_list(opts) do
      typed_message_statement(unquote(message_name), edge_ast, [label: label] ++ opts, env, meta)
    end

    defp statement_steps({unquote(message_name), meta, [edge_ast, label]}, env)
         when is_binary(label) do
      typed_message_statement(unquote(message_name), edge_ast, [label: label], env, meta)
    end

    defp statement_steps({unquote(message_name), meta, [edge_ast, opts]}, env)
         when is_list(opts) do
      typed_message_statement(unquote(message_name), edge_ast, opts, env, meta)
    end

    defp statement_steps({unquote(message_name), meta, [edge_ast]}, env) do
      typed_message_statement(unquote(message_name), edge_ast, [], env, meta)
    end
  end

  defp statement_steps({:|>, _meta, _args} = ast, env) do
    {message, participants} = message_from_piped_ast(ast, env)
    {message_declaration_steps(participants, message), env}
  end

  defp statement_steps({:~>, meta, _args} = ast, env) do
    {message, participants} = message_from_ast(ast, [], env, meta)
    {message_declaration_steps(participants, message), env}
  end

  defp statement_steps({:activate, meta, [participant_ast]}, env) do
    {id, participant} = endpoint_id(participant_ast, env, meta)
    {participant |> participant_steps() |> append_step({:activation, :activate, id}), env}
  end

  defp statement_steps({:deactivate, meta, [participant_ast]}, env) do
    {id, participant} = endpoint_id(participant_ast, env, meta)
    {participant |> participant_steps() |> append_step({:activation, :deactivate, id}), env}
  end

  defp statement_steps({name, meta, args}, env) when name in [:over, :left, :right] do
    note_statement(name, args, env, meta)
  end

  defp statement_steps({:between, meta, args}, env), do: between_note_statement(args, env, meta)
  defp statement_steps({:note, meta, args}, env), do: explicit_note_statement(args, env, meta)

  defp statement_steps({name, meta, args}, env)
       when name in [:loop, :opt, :alt, :par, :break, :critical] do
    fragment_block_statement(name, args, env, meta)
  end

  defp statement_steps({name, meta, args}, env) when name in [:otherwise, :else, :and] do
    fragment_arm_statement(name, args, env, meta)
  end

  defp statement_steps({name, meta, args} = ast, env) when is_atom(name) and is_list(args) do
    if participant_constructor?(ast) do
      participant = participant_from_constructor(ast, nil, meta)
      {[{:participant, participant}], env}
    else
      unsupported_statement!(ast, meta)
    end
  end

  defp statement_steps(other, _env), do: unsupported_statement!(other, nil)

  defp typed_message_statement(name, edge_ast, opts, env, meta) do
    opts = opts |> normalize_message_opts() |> Keyword.put(:type, message_type!(name))
    {message, participants} = message_from_ast(edge_ast, opts, env, meta)
    {message_declaration_steps(participants, message), env}
  end

  defp message_declaration_steps(participants, message) do
    participants
    |> Enum.reduce([{:message, message}], fn participant, steps ->
      [{:participant, participant} | steps]
    end)
    |> Enum.reverse()
  end

  defp participant_steps(nil), do: []
  defp participant_steps(participant), do: [{:participant, participant}]

  defp append_step(steps, step),
    do: steps |> Enum.reverse() |> then(&[step | &1]) |> Enum.reverse()

  defp message_from_piped_ast(ast, env) do
    {base, modifiers} = unwrap_pipe(ast, [])
    opts = modifiers |> Enum.reduce([], &modifier_opt/2) |> normalize_message_opts()
    message_from_ast(base, opts, env, line_meta(base))
  end

  defp modifier_opt({name, _meta, [value]}, acc) when name in [:on, :label] do
    Keyword.put(acc, :label, value)
  end

  defp modifier_opt({name, _meta, []}, acc) when name in @message_verbs do
    Keyword.put(acc, :type, message_type!(name))
  end

  defp modifier_opt({name, _meta, [label]}, acc)
       when name in @message_verbs and is_binary(label) do
    acc
    |> Keyword.put(:type, message_type!(name))
    |> Keyword.put(:label, label)
  end

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported sequence message modifier: #{Macro.to_string(other)}; " <>
            "use `on(value)`, `call(value)`, `async(value)`, or `reply(value)`"
  end

  defp message_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    {from, from_participant} = endpoint_id(from_ast, env, meta)
    {to, to_participant} = endpoint_id(to_ast, env, meta)

    participants =
      [from_participant, to_participant] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)

    opts = opts |> normalize_message_opts() |> Keyword.put_new(:type, :sync)

    {%{from: from, to: to, opts: opts}, participants}
  end

  defp message_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in sequence DSL, got #{Macro.to_string(other)}" <>
            line_suffix(meta)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env, var) do
      {:ok, id} ->
        {id, nil}

      :error ->
        raise ArgumentError, "unknown sequence participant variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, _env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if participant_constructor?(constructor) do
      participant = participant_from_constructor(constructor, nil, meta)
      {participant.id, participant}
    else
      raise ArgumentError,
            "unknown sequence participant constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported sequence endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a participant first, e.g. `api = participant(\"API\")`"
  end

  defp participant_from_constructor({name, meta, args}, var, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@participant_builders, name) ||
        raise ArgumentError,
              "unknown sequence participant constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    {id, opts} = participant_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
  end

  defp participant_constructor?({name, _meta, args}) when is_atom(name) and is_list(args),
    do: Map.has_key?(@participant_builders, name)

  defp note_statement(position, [participant_ast, text], env, meta) when is_binary(text) do
    {id, participant} = endpoint_id(participant_ast, env, meta)
    {participant |> participant_steps() |> append_step({:note, {position, id}, text}), env}
  end

  defp note_statement(position, args, _env, meta) do
    raise ArgumentError,
          "#{position}/2 notes require a participant and text, got #{inspect(args)}#{line_suffix(meta)}"
  end

  defp between_note_statement([left_ast, right_ast, text], env, meta) when is_binary(text) do
    {left, left_participant} = endpoint_id(left_ast, env, meta)
    {right, right_participant} = endpoint_id(right_ast, env, meta)

    steps =
      [left_participant, right_participant]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(&{:participant, &1})

    {append_step(steps, {:note, {:between, left, right}, text}), env}
  end

  defp between_note_statement(args, _env, meta) do
    raise ArgumentError,
          "between/3 notes require two participants and text, got #{inspect(args)}#{line_suffix(meta)}"
  end

  defp explicit_note_statement([{:over, _, [participant_ast]}, text], env, meta)
       when is_binary(text) do
    note_statement(:over, [participant_ast, text], env, meta)
  end

  defp explicit_note_statement([{:left, _, [participant_ast]}, text], env, meta)
       when is_binary(text) do
    note_statement(:left, [participant_ast, text], env, meta)
  end

  defp explicit_note_statement([{:right, _, [participant_ast]}, text], env, meta)
       when is_binary(text) do
    note_statement(:right, [participant_ast, text], env, meta)
  end

  defp explicit_note_statement([{:between, _, [left_ast, right_ast]}, text], env, meta)
       when is_binary(text) do
    between_note_statement([left_ast, right_ast, text], env, meta)
  end

  defp explicit_note_statement(args, _env, meta) do
    raise ArgumentError,
          "note/2 expects `over(participant)`, `left(participant)`, `right(participant)`, or `between(a, b)`#{line_suffix(meta)}; got #{inspect(args)}"
  end

  defp fragment_block_statement(kind, args, env, meta) do
    {block, args} = pop_do_block(args)
    label = fragment_label(args, meta)

    if is_nil(block) do
      raise ArgumentError, "#{kind}/2 fragment requires a do-block#{line_suffix(meta)}"
    end

    {nested_steps, _nested_env} = compile_statements(statements(block), env)

    steps =
      nested_steps
      |> List.insert_at(0, {:fragment, kind, label})
      |> append_step(:end_fragment)

    {steps, env}
  end

  defp fragment_arm_statement(kind, args, env, meta) do
    label = fragment_label(args, meta)
    fragment_kind = if kind == :otherwise, do: :else, else: kind
    {[{:fragment, fragment_kind, label}], env}
  end

  defp fragment_label([], _meta), do: nil
  defp fragment_label([label], _meta) when is_binary(label), do: label

  defp fragment_label(args, meta) do
    raise ArgumentError,
          "fragment label must be a string, got #{inspect(args)}#{line_suffix(meta)}"
  end

  defp participant_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "participant constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline sequence participant constructors need a label/id or `id:` option#{line_suffix(meta)}"
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
          "inline sequence participant label/id must be a string or atom, got #{inspect(other)}"
  end

  defp normalize_message_opts(opts) do
    opts
    |> normalize_label_alias(:with)
    |> normalize_message_aliases()
  end

  defp normalize_label_alias(opts, key) do
    {value, opts} = Keyword.pop(opts, key)
    if value == nil, do: opts, else: Keyword.put_new(opts, :label, value)
  end

  defp normalize_message_aliases(opts) do
    Enum.reduce(@message_verbs, opts, fn key, acc ->
      {value, acc} = Keyword.pop(acc, key)

      if value == nil do
        acc
      else
        acc
        |> Keyword.put_new(:type, message_type!(key))
        |> Keyword.put_new(:label, value)
      end
    end)
  end

  defp message_type!(name), do: Map.fetch!(@message_types, name)

  defp pipe_step({:participant, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.Sequence, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:message, %{from: from, to: to, opts: opts}}, acc) do
    quote do
      Choreo.Sequence.message(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp pipe_step({:activation, :activate, participant}, acc) do
    quote do
      Choreo.Sequence.activate(unquote(acc), unquote(Macro.escape(participant)))
    end
  end

  defp pipe_step({:activation, :deactivate, participant}, acc) do
    quote do
      Choreo.Sequence.deactivate(unquote(acc), unquote(Macro.escape(participant)))
    end
  end

  defp pipe_step({:note, position, text}, acc) do
    quote do
      Choreo.Sequence.note(unquote(acc), unquote(Macro.escape(position)), unquote(text))
    end
  end

  defp pipe_step({:fragment, kind, label}, acc) do
    quote do
      Choreo.Sequence.fragment(unquote(acc), unquote(kind), unquote(label))
    end
  end

  defp pipe_step(:end_fragment, acc) do
    quote do
      Choreo.Sequence.end_fragment(unquote(acc))
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in sequence DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
  end

  # Autocomplete helper stubs
  for verb <- [
        :activate,
        :actor,
        :alt,
        :async,
        :between,
        :break,
        :call,
        :critical,
        :deactivate,
        :else,
        :left,
        :loop,
        :message,
        :note,
        :opt,
        :otherwise,
        :over,
        :par,
        :participant,
        :publish,
        :reply,
        :request,
        :response,
        :return,
        :right,
        :service,
        :signal,
        :sync,
        :system,
        :user
      ] do
    def unquote(verb)(_arg1 \\ nil, _arg2 \\ nil, _opts \\ []) do
      raise "DSL constructor `#{unquote(verb)}` must be called inside a DSL block"
    end
  end
end
