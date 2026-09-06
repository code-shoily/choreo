defmodule Choreo.Sequence do
  @moduledoc """
  Sequence diagrams for Choreo.

  Sequence diagrams show how participants interact with each other over time.
  Unlike most other Choreo modules, this module is heavily skewed toward
  Mermaid's native `sequenceDiagram` syntax — GraphViz has no native
  sequence-diagram concept, so the DOT renderer is provided as a best-effort
  timeline-style fallback.

  ## Supported features

  - **Participants** and **Actors** (external roles)
  - **Synchronous**, **asynchronous**, **return**, and **self** messages
  - **Activation boxes** (`activate` / `deactivate`)
  - **Notes** (`over`, `left`, `right` of a participant, or `between` two)
  - **Loops** and fragments (`loop`, `opt`, `alt`/`else`, `par`, `break`, `critical`)

  ## Example

      iex> alias Choreo.Sequence
      iex> Sequence.new()
      ...> |> Sequence.add_actor(:user, label: "User")
      ...> |> Sequence.add_participant(:api, label: "API")
      ...> |> Sequence.add_participant(:db, label: "Database")
      ...> |> Sequence.message(:user, :api, label: "GET /accounts")
      ...> |> Sequence.activate(:api)
      ...> |> Sequence.message(:api, :db, label: "SELECT * FROM accounts")
      ...> |> Sequence.return(:db, :api, label: "rows")
      ...> |> Sequence.deactivate(:api)
      ...> |> Sequence.return(:api, :user, label: "200 OK")
      ...> |> Sequence.to_mermaid()
      ...> |> String.split("\\n")
      ...> |> Enum.take(4)
      ["sequenceDiagram", "    actor user as User", "    participant api as API", "    participant db as Database"]

  """

  alias __MODULE__

  defstruct graph: nil, edge_meta: %{}, events: [], next_order: 0, participants: []

  @type t :: %Sequence{}
  @type event_type :: :message | :activation | :note | :fragment
  @type message_type :: :sync | :async | :return | :self
  @type note_position ::
          {:over, atom()} | {:left, atom()} | {:right, atom()} | {:between, atom(), atom()}
  @type fragment_kind :: :loop | :opt | :alt | :else | :and | :par | :break | :critical

  @doc """
  Creates a new empty sequence diagram.
  """
  @spec new(keyword()) :: t()
  def new(_opts \\ []) do
    %Sequence{graph: Yog.Multi.new(:directed)}
  end

  # ---------------------------------------------------------------------
  # Participants
  # ---------------------------------------------------------------------

  @doc """
  Adds an actor (external person or system) to the diagram.

  ## Options

  - `:label` - display name (defaults to `Macro.camelize/1` of the id)
  - `:description` - longer description (used by analysis, not rendered)
  """
  @spec add_actor(t(), atom(), keyword()) :: t()
  def add_actor(%Sequence{} = seq, id, opts \\ []) when is_atom(id) do
    add_participant(seq, id, :actor, opts)
  end

  @doc """
  Adds a participant to the diagram.

  ## Options

  - `:label` - display name
  - `:description` - longer description
  """
  @spec add_participant(t(), atom(), keyword()) :: t()
  def add_participant(%Sequence{} = seq, id, opts \\ []) when is_atom(id) do
    add_participant(seq, id, :participant, opts)
  end

  # Re-adding an existing id silently replaces its metadata.
  defp add_participant(%Sequence{graph: g, participants: ps} = seq, id, type, opts) do
    label = opts[:label] || Macro.camelize(Atom.to_string(id))
    meta = %{node_type: type, label: label, description: opts[:description]}
    g = Yog.Multi.add_node(g, id, meta)
    ps = if id in ps, do: ps, else: [id | ps]
    %Sequence{seq | graph: g, participants: ps}
  end

  # ---------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------

  @doc """
  Adds a message from `from` to `to`.

  ## Options

  - `:label` - message label
  - `:type` - `:sync` (default), `:async`, `:return`, or `:self`

  A self-message is automatically detected when `from == to`.
  """
  @spec message(t(), atom(), atom(), keyword()) :: t()
  def message(%Sequence{} = seq, from, to, opts \\ [])
      when is_atom(from) and is_atom(to) do
    type = if from == to, do: :self, else: opts[:type] || :sync

    {g, eid} = Yog.Multi.add_edge(seq.graph, from, to, 1)

    meta = %{
      order: seq.next_order,
      label: opts[:label],
      type: type,
      from: from,
      to: to
    }

    seq = %Sequence{
      seq
      | graph: g,
        edge_meta: Map.put(seq.edge_meta, eid, meta)
    }

    append_event(seq, %{type: :message, order: seq.next_order, edge_id: eid})
  end

  @doc """
  Adds an asynchronous message.
  """
  @spec async(t(), atom(), atom(), keyword()) :: t()
  def async(%Sequence{} = seq, from, to, opts \\ []) do
    message(seq, from, to, Keyword.put(opts, :type, :async))
  end

  @doc """
  Adds a return message.
  """
  @spec return(t(), atom(), atom(), keyword()) :: t()
  def return(%Sequence{} = seq, from, to, opts \\ []) do
    message(seq, from, to, Keyword.put(opts, :type, :return))
  end

  @doc """
  Adds a self-message on the given participant.
  """
  @spec self_message(t(), atom(), keyword()) :: t()
  def self_message(%Sequence{} = seq, participant, opts \\ []) do
    message(seq, participant, participant, opts)
  end

  # ---------------------------------------------------------------------
  # Activations
  # ---------------------------------------------------------------------

  @doc """
  Emits an `activate` event for the given participant.
  """
  @spec activate(t(), atom()) :: t()
  def activate(%Sequence{} = seq, participant) when is_atom(participant) do
    append_event(seq, %{
      type: :activation,
      order: seq.next_order,
      participant: participant,
      action: :activate
    })
  end

  @doc """
  Emits a `deactivate` event for the given participant.
  """
  @spec deactivate(t(), atom()) :: t()
  def deactivate(%Sequence{} = seq, participant) when is_atom(participant) do
    append_event(seq, %{
      type: :activation,
      order: seq.next_order,
      participant: participant,
      action: :deactivate
    })
  end

  # ---------------------------------------------------------------------
  # Notes
  # ---------------------------------------------------------------------

  @doc """
  Adds a note to the diagram.

  `position` can be:

  - `{:over, :alice}`
  - `{:left, :alice}`
  - `{:right, :alice}`
  - `{:between, :alice, :bob}`
  """
  @spec note(t(), note_position(), String.t()) :: t()
  def note(%Sequence{} = seq, position, text) when is_binary(text) do
    append_event(seq, %{type: :note, order: seq.next_order, position: position, text: text})
  end

  # ---------------------------------------------------------------------
  # Fragments
  # ---------------------------------------------------------------------

  @doc """
  Starts a fragment (loop, opt, alt, par, break, critical).

  ## Examples

      seq
      |> Sequence.fragment(:loop, "for each item")
      |> Sequence.message(:a, :b, label: "process")
      |> Sequence.end_fragment()

      seq
      |> Sequence.fragment(:alt, "x > 0")
      |> Sequence.message(:a, :b, label: "positive")
      |> Sequence.fragment(:else, "otherwise")
      |> Sequence.message(:a, :b, label: "negative")
      |> Sequence.end_fragment()
  """
  @spec fragment(t(), fragment_kind(), String.t() | nil) :: t()
  def fragment(%Sequence{} = seq, kind, label \\ nil)
      when kind in [:loop, :opt, :alt, :else, :and, :par, :break, :critical] do
    action = if kind in [:else, :and], do: :arm, else: :start

    append_event(seq, %{
      type: :fragment,
      order: seq.next_order,
      kind: kind,
      label: label,
      action: action
    })
  end

  @doc """
  Ends the most recently started fragment.
  """
  @spec end_fragment(t()) :: t()
  def end_fragment(%Sequence{} = seq) do
    append_event(seq, %{
      type: :fragment,
      order: seq.next_order,
      kind: nil,
      label: nil,
      action: :end
    })
  end

  # ---------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------

  @doc """
  Returns all participants/actors in the diagram.
  """
  @spec participants(t()) :: [atom()]
  def participants(%Sequence{participants: ps}) do
    Enum.reverse(ps)
  end

  @doc """
  Returns metadata for a participant.
  """
  @spec participant(t(), atom()) :: map() | nil
  def participant(%Sequence{graph: g}, id) do
    Map.get(g.nodes, id)
  end

  @doc """
  Returns a map of participant IDs to display labels.
  """
  @spec participant_labels(t()) :: %{atom() => String.t()}
  def participant_labels(%Sequence{graph: g}) do
    Map.new(g.nodes, fn {id, meta} ->
      label = meta[:label] || Macro.camelize(Atom.to_string(id))
      {id, label}
    end)
  end

  @doc """
  Returns all ordered events in the diagram.
  """
  @spec events(t()) :: [map()]
  def events(%Sequence{events: events}) do
    Enum.reverse(events)
  end

  @doc """
  Returns messages in chronological order.
  """
  @spec messages(t()) :: [map()]
  def messages(%Sequence{} = seq) do
    seq
    |> events()
    |> Enum.filter(&(&1.type == :message))
    |> Enum.map(fn ev ->
      meta = Map.get(seq.edge_meta, ev.edge_id, %{})
      Map.merge(ev, meta)
    end)
  end

  # ---------------------------------------------------------------------
  # Render helpers
  # ---------------------------------------------------------------------

  @doc """
  Renders the diagram as a Mermaid sequence diagram.
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%Sequence{} = seq, opts \\ []) do
    Choreo.Sequence.Render.Mermaid.to_mermaid(seq, opts)
  end

  @doc """
  Renders the diagram as a DOT graph (best-effort timeline view).
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%Sequence{} = seq, opts \\ []) do
    Choreo.Sequence.Render.DOT.to_dot(seq, opts)
  end

  @doc """
  Returns a theme for `Choreo.Sequence`.

  ## Examples

      iex> theme = Choreo.Sequence.theme(:default, graph_rankdir: :lr)
      iex> theme.graph_rankdir
      :lr
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.Sequence.Render.DOT.theme(name, overrides)
  end

  # ---------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------

  defp append_event(%Sequence{events: events, next_order: order} = seq, event) do
    %Sequence{seq | events: [event | events], next_order: order + 1}
  end
end

defimpl Choreo.Mermaid, for: Choreo.Sequence do
  def to_mermaid(diagram, opts) do
    Choreo.Sequence.Render.Mermaid.to_mermaid(diagram, opts)
  end
end

defimpl Choreo.DOT, for: Choreo.Sequence do
  def to_dot(diagram, opts) do
    Choreo.Sequence.Render.DOT.to_dot(diagram, opts)
  end
end
