defmodule Choreo.Lab.DSL.FSM do
  @moduledoc """
  Experimental Livebook-friendly DSL for sketching finite-state machines.

  This Lab DSL compiles to the stable, pipe-first `Choreo.FSM` builders and
  returns an ordinary `%Choreo.FSM{}`. It follows the same identity rule as the
  infrastructure Lab DSL: in assignment form, the variable name becomes the node
  id and the string becomes the display label; in inline form, the string is
  slugged into an id and also used as the label.

  ## Examples

      iex> import Choreo.Lab.DSL.FSM
      ...> machine = fsm do
      ...>   idle = initial("Idle")
      ...>   authorized = state("Authorized")
      ...>   denied = final("Denied")
      ...>
      ...>   idle ~> authorized |> on("token valid")
      ...>   edge idle ~> denied, with: "token invalid"
      ...> end
      iex> Choreo.FSM.initial_state(machine)
      :idle
      iex> Choreo.FSM.final_states(machine)
      [:denied]
      iex> Choreo.FSM.transitions(machine) |> Enum.sort()
      [{:idle, :authorized, "token valid"}, {:idle, :denied, "token invalid"}]

  Transition labels can use pipe modifiers or the explicit `edge` form:

      idle ~> authorized |> on("token valid")
      idle ~> authorized |> label("token valid")
      idle ~> authorized |> guard("claims.tenant == request.tenant")
      edge idle ~> denied, "token invalid"
      edge idle ~> denied, with: "token invalid"
      edge idle ~> denied, label: "token invalid"
  """

  @type state_decl :: %{id: Yog.node_id(), builder: atom(), opts: keyword()}
  @type transition_decl :: %{from: Yog.node_id(), to: Yog.node_id(), opts: keyword()}

  @state_verbs [:state, :initial, :init, :start, :final, :done]

  @state_builders %{
    state: :add_state,
    initial: :add_initial_state,
    init: :add_initial_state,
    start: :add_initial_state,
    final: :add_final_state,
    done: :add_final_state
  }

  @doc """
  Returns the vocabulary supported by the FSM DSL.

      iex> verbs = Choreo.Lab.DSL.FSM.verbs()
      iex> :initial in verbs.states
      true
      iex> :~> in verbs.edges
      true
      iex> :guard in verbs.modifiers
      true
  """
  @spec verbs() :: %{
          states: [atom()],
          edges: [atom()],
          modifiers: [atom()],
          options: [atom()]
        }
  def verbs do
    %{
      states: @state_verbs,
      edges: [:~>, :edge],
      modifiers: [:on, :label, :guard],
      options: [:label, :with, :guard, :id]
    }
  end

  @doc """
  Builds a `%Choreo.FSM{}` from a compact Lab DSL block.
  """
  defmacro fsm(do: block) do
    compile(block)
  end

  defmacro fsm(opts, do: block) do
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

    Enum.reduce(steps, quote(do: Choreo.FSM.new(unquote(Macro.escape(opts)))), &pipe_step/2)
  end

  defp statements({:__block__, _meta, list}), do: list
  defp statements(nil), do: []
  defp statements(single), do: [single]

  defp statement_steps({:=, meta, [{var, _, context}, constructor]}, env)
       when is_atom(var) and is_atom(context) do
    state = state_from_constructor(constructor, var, meta)
    {[{:state, state}], Map.put(env, var, state.id)}
  end

  defp statement_steps({:edge, meta, [edge_ast, label]}, env) when is_binary(label) do
    {transition, states} = transition_from_ast(edge_ast, [label: label], env, meta)
    {transition_declaration_steps(states, transition), env}
  end

  defp statement_steps({:edge, meta, [edge_ast, opts]}, env) when is_list(opts) do
    {transition, states} =
      transition_from_ast(edge_ast, normalize_transition_opts(opts), env, meta)

    {transition_declaration_steps(states, transition), env}
  end

  defp statement_steps({:edge, meta, [edge_ast]}, env) do
    {transition, states} = transition_from_ast(edge_ast, [], env, meta)
    {transition_declaration_steps(states, transition), env}
  end

  defp statement_steps({:|>, _meta, _args} = ast, env) do
    {transition, states} = transition_from_piped_ast(ast, env)
    {transition_declaration_steps(states, transition), env}
  end

  defp statement_steps({:~>, meta, _args} = ast, env) do
    {transition, states} = transition_from_ast(ast, [], env, meta)
    {transition_declaration_steps(states, transition), env}
  end

  defp statement_steps({name, meta, args} = ast, env) when is_atom(name) and is_list(args) do
    if Map.has_key?(@state_builders, name) do
      state = state_from_constructor(ast, nil, meta)
      {[{:state, state}], env}
    else
      unsupported_statement!(ast, meta)
    end
  end

  defp statement_steps(other, _env), do: unsupported_statement!(other, nil)

  defp transition_declaration_steps(states, transition) do
    states
    |> Enum.reduce([{:transition, transition}], fn state, steps -> [{:state, state} | steps] end)
    |> Enum.reverse()
  end

  defp transition_from_piped_ast(ast, env) do
    {base, modifiers} = unwrap_pipe(ast, [])
    opts = modifiers |> Enum.reduce([], &modifier_opt/2) |> normalize_transition_opts()
    transition_from_ast(base, opts, env, line_meta(base))
  end

  defp unwrap_pipe({:|>, _meta, [left, right]}, acc), do: unwrap_pipe(left, [right | acc])
  defp unwrap_pipe(base, acc), do: {base, acc}

  defp modifier_opt({name, _meta, [value]}, acc) when name in [:on, :label] do
    Keyword.put(acc, :label, value)
  end

  defp modifier_opt({:guard, _meta, [value]}, acc), do: Keyword.put(acc, :guard, value)

  defp modifier_opt(other, _acc) do
    raise ArgumentError,
          "unsupported FSM transition modifier: #{Macro.to_string(other)}; " <>
            "use `on(value)`, `label(value)`, or `guard(value)`"
  end

  defp transition_from_ast({:~>, meta, [from_ast, to_ast]}, opts, env, _statement_meta) do
    opts = require_transition_label_or_guard!(opts, meta)
    {from, from_state} = endpoint_id(from_ast, env, meta)
    {to, to_state} = endpoint_id(to_ast, env, meta)
    states = [from_state, to_state] |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)

    {%{from: from, to: to, opts: opts}, states}
  end

  defp transition_from_ast(other, _opts, _env, meta) do
    raise ArgumentError,
          "expected `from ~> to` in FSM DSL, got #{Macro.to_string(other)}" <> line_suffix(meta)
  end

  defp endpoint_id({var, _meta, context}, env, meta) when is_atom(var) and is_atom(context) do
    case Map.fetch(env, var) do
      {:ok, id} -> {id, nil}
      :error -> raise ArgumentError, "unknown FSM state variable `#{var}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id({name, meta, args} = constructor, _env, _statement_meta)
       when is_atom(name) and is_list(args) do
    if Map.has_key?(@state_builders, name) do
      state = state_from_constructor(constructor, nil, meta)
      {state.id, state}
    else
      raise ArgumentError, "unknown FSM state constructor `#{name}`#{line_suffix(meta)}"
    end
  end

  defp endpoint_id(other, _env, meta) do
    raise ArgumentError,
          "unsupported FSM transition endpoint #{Macro.to_string(other)}#{line_suffix(meta)}; " <>
            "bind a state first, e.g. `idle = initial(\"Idle\")`"
  end

  defp state_from_constructor({name, meta, args}, var, _statement_meta)
       when is_atom(name) and is_list(args) do
    builder =
      Map.get(@state_builders, name) ||
        raise ArgumentError, "unknown FSM state constructor `#{name}`#{line_suffix(meta)}"

    {opts, positional} = pop_trailing_opts(args)
    {id, opts} = state_id_and_opts(var, positional, opts, meta)
    %{id: id, builder: builder, opts: opts}
  end

  defp state_from_constructor(other, _var, meta) do
    raise ArgumentError,
          "expected FSM state constructor, got #{Macro.to_string(other)}#{line_suffix(meta)}"
  end

  defp pop_trailing_opts(args) do
    case List.last(args) do
      last when is_list(last) ->
        if Keyword.keyword?(last), do: {last, Enum.drop(args, -1)}, else: {[], args}

      _other ->
        {[], args}
    end
  end

  defp state_id_and_opts(var, positional, opts, meta) do
    {explicit_id, opts} = Keyword.pop(opts, :id)

    cond do
      length(positional) > 1 ->
        raise ArgumentError,
              "state constructors take at most one positional label/id#{line_suffix(meta)}"

      explicit_id != nil ->
        {explicit_id, maybe_put_label(opts, List.first(positional))}

      var != nil ->
        {var, maybe_put_label(opts, List.first(positional))}

      positional != [] ->
        label_or_id = List.first(positional)
        {id_from_label(label_or_id), maybe_put_label(opts, label_or_id)}

      true ->
        raise ArgumentError,
              "inline FSM state constructors need a label/id or `id:` option#{line_suffix(meta)}"
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
          "inline FSM state label/id must be a string or atom, got #{inspect(other)}"
  end

  defp slug_atom(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> raise ArgumentError, "cannot derive an FSM state id from an empty label"
      slug -> String.to_atom(slug)
    end
  end

  defp normalize_transition_opts(opts) do
    {with_label, opts} = Keyword.pop(opts, :with)

    if with_label != nil do
      Keyword.put_new(opts, :label, with_label)
    else
      opts
    end
  end

  defp require_transition_label_or_guard!(opts, meta) do
    if Keyword.has_key?(opts, :label) or Keyword.has_key?(opts, :guard) do
      opts
    else
      raise ArgumentError,
            "FSM transitions require `on(value)`, `label(value)`, `guard(value)`, " <>
              "or `edge from ~> to, with: value`#{line_suffix(meta)}"
    end
  end

  defp pipe_step({:state, %{id: id, builder: builder, opts: opts}}, acc) do
    quote do
      apply(Choreo.FSM, unquote(builder), [
        unquote(acc),
        unquote(Macro.escape(id)),
        unquote(Macro.escape(opts))
      ])
    end
  end

  defp pipe_step({:transition, %{from: from, to: to, opts: opts}}, acc) do
    quote do
      Choreo.FSM.add_transition(
        unquote(acc),
        unquote(Macro.escape(from)),
        unquote(Macro.escape(to)),
        unquote(Macro.escape(opts))
      )
    end
  end

  defp unsupported_statement!(ast, meta) do
    raise ArgumentError,
          "unsupported statement in FSM DSL: #{Macro.to_string(ast)}#{line_suffix(meta)}"
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
