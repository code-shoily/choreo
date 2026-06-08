defmodule Choreo.Planner do
  @moduledoc """
  Project planning and task management diagram builder on top of Yog.

  `Choreo.Planner` models projects as typed multigraphs where tasks,
  milestones, users, and labels are nodes and relationships (hierarchy,
  dependencies, assignments, tags) are edges.

  It supports three Mermaid render targets:

    * **Kanban** — native Mermaid `kanban` syntax with status columns
    * **Gantt** — native Mermaid `gantt` syntax with dependency scheduling
    * **Flowchart** — standard `graph TD` dependency network

  Analysis functions identify ready work, blocked tasks, critical paths,
  and bottlenecks.

  ## Quick Start

      project =
        Choreo.Planner.new("Launch v1")
        |> Choreo.Planner.add_milestone(:v1, title: "V1 Launch")
        |> Choreo.Planner.add_task(:design, title: "Design", status: :done, estimate_hours: 16)
        |> Choreo.Planner.add_task(:impl, title: "Implement", status: :backlog, estimate_hours: 24)
        |> Choreo.Planner.add_task(:test, title: "Test", status: :backlog, estimate_hours: 8)
        |> Choreo.Planner.add_user(:alice, name: "Alice")
        |> Choreo.Planner.contains(:v1, :design)
        |> Choreo.Planner.contains(:v1, :impl)
        |> Choreo.Planner.contains(:v1, :test)
        |> Choreo.Planner.depends_on(:impl, :design)
        |> Choreo.Planner.depends_on(:test, :impl)
        |> Choreo.Planner.assign(:design, :alice)

      Choreo.Planner.ready(project)
      # => [{:impl, %{status: :backlog, ...}}]

      Choreo.Planner.Analysis.critical_path(project, milestone: :v1)
      # => {:ok, [:design, :impl, :test], total_estimate: 48}

      kanban = Choreo.Planner.to_mermaid(project, syntax: :kanban)
      gantt  = Choreo.Planner.to_mermaid(project, syntax: :gantt)
      flow   = Choreo.Planner.to_mermaid(project, syntax: :flowchart)

  ## Node Types

  | Type | Builder | Default Properties |
  |------|---------|-------------------|
  | `:task` | `add_task/3` | `status: :backlog`, `priority: :medium` |
  | `:milestone` | `add_milestone/3` | none |
  | `:user` | `add_user/3` | none |
  | `:label` | `add_label/3` | none |

  ## Edge Types

  | Type | Builder | Direction | Meaning |
  |------|---------|-----------|---------|
  | `:contains` | `contains/3` | milestone → task | Hierarchy |
  | `:depends_on` | `depends_on/3` | dependency → task | Finish-to-start |
  | `:blocks` | `blocks/3` | blocker → blocked | Semantic blocker |
  | `:assigned_to` | `assign/3` | task → user | Ownership |
  | `:tagged_with` | `tag/3` | task → label | Categorization |
  | `:relates_to` | `relates/3` | bidirectional | Loose association |
  """

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          name: String.t() | nil
        }

  defstruct graph: nil, edge_meta: %{}, name: nil

  # ============================================================================
  # Construction
  # ============================================================================

  @doc """
  Creates a new empty planner.
  """
  @spec new(keyword() | String.t() | nil) :: t()
  def new(name_or_opts \\ [])

  def new(nil), do: new([])

  def new(name) when is_binary(name) do
    %__MODULE__{
      name: name,
      graph: Yog.Multi.directed(),
      edge_meta: %{}
    }
  end

  def new(opts) when is_list(opts) do
    %__MODULE__{
      name: Keyword.get(opts, :name),
      graph: Yog.Multi.directed(),
      edge_meta: %{}
    }
  end

  # ============================================================================
  # Builder — Nodes
  # ============================================================================

  @doc """
  Adds a task node.

  ## Options

    * `:status` — `:backlog` (default), `:todo`, `:in_progress`, `:in_review`, `:done`, `:cancelled`
    * `:priority` — `:low`, `:medium` (default), `:high`, `:critical`
    * `:title` — display name
    * `:due_date` — target date (`Date.t()`)
    * `:estimate_hours` — numeric estimate
    * `:actual_hours` — numeric actual
  """
  @spec add_task(t(), Yog.node_id(), keyword()) :: t()
  def add_task(%__MODULE__{graph: g} = planner, id, opts \\ []) do
    data = Map.merge(%{node_type: :task, status: :backlog, priority: :medium}, Map.new(opts))
    %{planner | graph: Yog.Multi.add_node(g, id, data)}
  end

  @doc """
  Adds a milestone node.

  ## Options

    * `:title` — display name
    * `:due_date` — target date
  """
  @spec add_milestone(t(), Yog.node_id(), keyword()) :: t()
  def add_milestone(%__MODULE__{graph: g} = planner, id, opts \\ []) do
    data = Map.merge(%{node_type: :milestone}, Map.new(opts))
    %{planner | graph: Yog.Multi.add_node(g, id, data)}
  end

  @doc """
  Adds a user node.

  ## Options

    * `:name` — display name
    * `:email` — contact email
  """
  @spec add_user(t(), Yog.node_id(), keyword()) :: t()
  def add_user(%__MODULE__{graph: g} = planner, id, opts \\ []) do
    data = Map.merge(%{node_type: :user}, Map.new(opts))
    %{planner | graph: Yog.Multi.add_node(g, id, data)}
  end

  @doc """
  Adds a label node for categorizing tasks.

  ## Options

    * `:title` — display name
  """
  @spec add_label(t(), Yog.node_id(), keyword()) :: t()
  def add_label(%__MODULE__{graph: g} = planner, id, opts \\ []) do
    data = Map.merge(%{node_type: :label}, Map.new(opts))
    %{planner | graph: Yog.Multi.add_node(g, id, data)}
  end

  @doc """
  Updates an existing task node's properties.

  Merges the given options into the task's current data.
  Raises `ArgumentError` if the node does not exist or is not a task.
  """
  @spec update_task(t(), Yog.node_id(), keyword()) :: t()
  def update_task(%__MODULE__{graph: g} = planner, id, opts) do
    require_node!(g, id, :task, "update_task")
    current = Map.fetch!(g.nodes, id)
    %{planner | graph: Yog.Multi.add_node(g, id, Map.merge(current, Map.new(opts)))}
  end

  @doc """
  Removes a task node and all edges connected to it.
  """
  @spec remove_task(t(), Yog.node_id()) :: t()
  def remove_task(%__MODULE__{graph: g, edge_meta: meta} = planner, id) do
    new_graph = Yog.Multi.remove_node(g, id)
    new_meta = Map.take(meta, Map.keys(new_graph.edges))
    %{planner | graph: new_graph, edge_meta: new_meta}
  end

  # ============================================================================
  # Builder — Edges
  # ============================================================================

  @doc """
  Parent -> child containment edge.

  The parent must be a milestone and the child must be a task.
  """
  @spec contains(t(), Yog.node_id(), Yog.node_id()) :: t()
  def contains(%__MODULE__{} = planner, parent, child) do
    planner =
      planner
      |> ensure_node(parent, :milestone)
      |> ensure_node(child, :task)

    add_edge(planner, parent, child, %{type: :contains})
  end

  @doc """
  Declares that `task` depends on `dependency`.

  Creates an edge `dependency -> task` meaning *dependency must finish
  before task can start*. Both must be tasks.
  """
  @spec depends_on(t(), Yog.node_id(), Yog.node_id()) :: t()
  def depends_on(%__MODULE__{} = planner, task, dependency) do
    planner =
      planner
      |> ensure_node(task, :task)
      |> ensure_node(dependency, :task)

    add_edge(planner, dependency, task, %{type: :depends_on})
  end

  @doc """
  Declares that `blocker` blocks `blocked`.

  Semantically identical to `depends_on/3` but carries blocking intent.
  Both must be tasks.
  """
  @spec blocks(t(), Yog.node_id(), Yog.node_id()) :: t()
  def blocks(%__MODULE__{} = planner, blocker, blocked) do
    planner =
      planner
      |> ensure_node(blocker, :task)
      |> ensure_node(blocked, :task)

    add_edge(planner, blocker, blocked, %{type: :blocks})
  end

  @doc """
  Assigns a task to a user. Edge: task -> user.
  """
  @spec assign(t(), Yog.node_id(), Yog.node_id()) :: t()
  def assign(%__MODULE__{} = planner, task, user) do
    planner =
      planner
      |> ensure_node(task, :task)
      |> ensure_node(user, :user)

    add_edge(planner, task, user, %{type: :assigned_to})
  end

  @doc """
  Tags a task with a label. Edge: task -> label.
  """
  @spec tag(t(), Yog.node_id(), Yog.node_id()) :: t()
  def tag(%__MODULE__{} = planner, task, label) do
    planner =
      planner
      |> ensure_node(task, :task)
      |> ensure_node(label, :label)

    add_edge(planner, task, label, %{type: :tagged_with})
  end

  @doc """
  Creates a bidirectional `:relates_to` relationship between two nodes.
  """
  @spec relates(t(), Yog.node_id(), Yog.node_id()) :: t()
  def relates(%__MODULE__{} = planner, a, b) do
    planner =
      planner
      |> ensure_existing_node!(a)
      |> ensure_existing_node!(b)

    {g1, eid1} = Yog.Multi.add_edge(planner.graph, a, b, 1)
    meta1 = Map.put(planner.edge_meta, eid1, %{type: :relates_to})

    {g2, eid2} = Yog.Multi.add_edge(g1, b, a, 1)
    meta2 = Map.put(meta1, eid2, %{type: :relates_to})

    %{planner | graph: g2, edge_meta: meta2}
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all task nodes as `{id, data}` tuples.
  """
  @spec tasks(t()) :: [{Yog.node_id(), map()}]
  def tasks(%__MODULE__{graph: g}), do: nodes_of_type(g, :task)

  @doc """
  Returns all milestone nodes as `{id, data}` tuples.
  """
  @spec milestones(t()) :: [{Yog.node_id(), map()}]
  def milestones(%__MODULE__{graph: g}), do: nodes_of_type(g, :milestone)

  @doc """
  Returns all user nodes as `{id, data}` tuples.
  """
  @spec users(t()) :: [{Yog.node_id(), map()}]
  def users(%__MODULE__{graph: g}), do: nodes_of_type(g, :user)

  @doc """
  Returns all label nodes as `{id, data}` tuples.
  """
  @spec labels(t()) :: [{Yog.node_id(), map()}]
  def labels(%__MODULE__{graph: g}), do: nodes_of_type(g, :label)

  @doc """
  Returns tasks filtered by status.
  """
  @spec tasks_by_status(t(), atom()) :: [{Yog.node_id(), map()}]
  def tasks_by_status(%__MODULE__{graph: g}, status) do
    g.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :task and data[:status] == status end)
    |> Enum.sort_by(fn {id, _} -> id end)
  end

  @doc """
  Returns child task IDs for a given milestone (connected via `:contains` edge).
  """
  @spec children(t(), Yog.node_id()) :: [Yog.node_id()]
  def children(%__MODULE__{} = planner, id) do
    planner
    |> outgoing_of_type(id, :contains)
    |> Enum.map(fn {_eid, _from, to, _w} -> to end)
  end

  @doc """
  Returns all parent milestone IDs for a given task.
  """
  @spec parents(t(), Yog.node_id()) :: [Yog.node_id()]
  def parents(%__MODULE__{} = planner, id) do
    planner
    |> incoming_of_type(id, :contains)
    |> Enum.map(fn {_eid, from, _to, _w} -> from end)
  end

  @doc """
  Returns the parent milestone ID for a given task, or `nil`.

  If a task is contained in multiple milestones, this returns the first one
  found. Use `parents/2` to retrieve the full list.
  """
  @spec parent(t(), Yog.node_id()) :: Yog.node_id() | nil
  def parent(%__MODULE__{} = planner, id) do
    planner
    |> parents(id)
    |> List.first()
  end

  @doc """
  Returns the IDs of nodes that `id` depends on.

  Includes both `:depends_on` and `:blocks` edges.
  """
  @spec dependencies(t(), Yog.node_id()) :: [Yog.node_id()]
  def dependencies(%__MODULE__{} = planner, id) do
    planner
    |> incoming_of_types(id, [:depends_on, :blocks])
    |> Enum.map(fn {_eid, from, _to, _w} -> from end)
  end

  @doc """
  Returns the IDs of nodes that depend on `id`.

  Includes both `:depends_on` and `:blocks` edges.
  """
  @spec dependents(t(), Yog.node_id()) :: [Yog.node_id()]
  def dependents(%__MODULE__{} = planner, id) do
    planner
    |> outgoing_of_types(id, [:depends_on, :blocks])
    |> Enum.map(fn {_eid, _from, to, _w} -> to end)
  end

  @doc """
  Returns all user IDs assigned to a task.
  """
  @spec assignees(t(), Yog.node_id()) :: [Yog.node_id()]
  def assignees(%__MODULE__{} = planner, id) do
    planner
    |> outgoing_of_type(id, :assigned_to)
    |> Enum.map(fn {_eid, _from, to, _w} -> to end)
  end

  @doc """
  Returns the user ID assigned to a task, or `nil`.

  If a task is assigned to multiple users, this returns the first one found.
  Use `assignees/2` to retrieve the full list.
  """
  @spec assignee(t(), Yog.node_id()) :: Yog.node_id() | nil
  def assignee(%__MODULE__{} = planner, id) do
    planner
    |> assignees(id)
    |> List.first()
  end

  @doc """
  Returns all task IDs assigned to a given user.
  """
  @spec assigned_tasks(t(), Yog.node_id()) :: [Yog.node_id()]
  def assigned_tasks(%__MODULE__{} = planner, user_id) do
    planner
    |> incoming_of_type(user_id, :assigned_to)
    |> Enum.map(fn {_eid, from, _to, _w} -> from end)
  end

  @doc """
  Returns all edges with their metadata as `{from, to, weight, meta}` tuples.
  """
  @spec edges_with_meta(t()) :: [{Yog.node_id(), Yog.node_id(), any(), map()}]
  def edges_with_meta(%__MODULE__{graph: g, edge_meta: meta}) do
    g.edges
    |> Enum.map(fn {eid, {from, to, weight}} ->
      {from, to, weight, Map.get(meta, eid, %{})}
    end)
    |> Enum.sort_by(fn {from, to, _, _} -> {from, to} end)
  end

  @doc """
  Returns the raw `Yog.Multi.Graph` struct underpinning the planner.
  """
  @spec to_graph(t()) :: Yog.Multi.Graph.t()
  def to_graph(%__MODULE__{graph: g}), do: g

  # ============================================================================
  # Convenience renderers
  # ============================================================================

  @doc """
  Renders the planner to a Mermaid diagram string.

  ## Options

    * `:syntax` — `:kanban` (default), `:kanban_compat`, `:gantt`, or `:flowchart`
    * Other options passed to the specific renderer
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = planner, opts \\ []) do
    syntax = Keyword.get(opts, :syntax, :kanban)
    opts = Keyword.put_new(opts, :syntax, syntax)
    Choreo.Planner.Render.Mermaid.to_mermaid(planner, opts)
  end

  @doc """
  Renders the planner to a DOT (Graphviz) diagram string.
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = planner, opts \\ []) do
    Choreo.Planner.Render.DOT.to_dot(planner, opts)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp add_edge(%__MODULE__{graph: g, edge_meta: meta} = planner, from, to, edge_data) do
    {new_graph, eid} = Yog.Multi.add_edge(g, from, to, 1)
    new_meta = Map.put(meta, eid, edge_data)
    %{planner | graph: new_graph, edge_meta: new_meta}
  end

  defp nodes_of_type(g, type) do
    g.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == type end)
    |> Enum.sort_by(fn {id, _} -> id end)
  end

  defp outgoing_of_type(%__MODULE__{graph: g, edge_meta: meta}, id, type) do
    eids = Map.get(g.out_edge_ids, id, MapSet.new())

    Enum.filter(MapSet.to_list(eids), fn eid ->
      Map.get(meta, eid, %{})[:type] == type
    end)
    |> Enum.map(fn eid ->
      {from, to, weight} = Map.fetch!(g.edges, eid)
      {eid, from, to, weight}
    end)
  end

  defp outgoing_of_types(%__MODULE__{graph: g, edge_meta: meta}, id, types) do
    eids = Map.get(g.out_edge_ids, id, MapSet.new())

    Enum.filter(MapSet.to_list(eids), fn eid ->
      Map.get(meta, eid, %{})[:type] in types
    end)
    |> Enum.map(fn eid ->
      {from, to, weight} = Map.fetch!(g.edges, eid)
      {eid, from, to, weight}
    end)
  end

  defp incoming_of_type(%__MODULE__{graph: g, edge_meta: meta}, id, type) do
    eids = Map.get(g.in_edge_ids, id, MapSet.new())

    Enum.filter(MapSet.to_list(eids), fn eid ->
      Map.get(meta, eid, %{})[:type] == type
    end)
    |> Enum.map(fn eid ->
      {from, to, weight} = Map.fetch!(g.edges, eid)
      {eid, from, to, weight}
    end)
  end

  defp incoming_of_types(%__MODULE__{graph: g, edge_meta: meta}, id, types) do
    eids = Map.get(g.in_edge_ids, id, MapSet.new())

    Enum.filter(MapSet.to_list(eids), fn eid ->
      Map.get(meta, eid, %{})[:type] in types
    end)
    |> Enum.map(fn eid ->
      {from, to, weight} = Map.fetch!(g.edges, eid)
      {eid, from, to, weight}
    end)
  end

  defp require_node!(g, id, expected_type, caller) do
    case Map.get(g.nodes, id) do
      nil ->
        raise ArgumentError, "#{caller}: node #{inspect(id)} does not exist"

      data ->
        actual = data[:node_type]

        if actual != expected_type do
          raise ArgumentError,
                "#{caller}: expected #{inspect(id)} to be a #{expected_type}, got #{actual}"
        end
    end
  end

  defp ensure_node(planner, id, expected_type) do
    case Map.get(planner.graph.nodes, id) do
      nil ->
        case expected_type do
          :task -> add_task(planner, id, title: to_string(id))
          :milestone -> add_milestone(planner, id, title: to_string(id))
          :user -> add_user(planner, id, name: to_string(id))
          :label -> add_label(planner, id, title: to_string(id))
          other -> raise ArgumentError, "unsupported node type: #{inspect(other)}"
        end

      data ->
        actual = data[:node_type]

        if actual != expected_type do
          raise ArgumentError,
                "expected #{inspect(id)} to be a #{expected_type}, got #{actual}"
        end

        planner
    end
  end

  defp ensure_existing_node!(planner, id) do
    unless Map.has_key?(planner.graph.nodes, id) do
      raise ArgumentError, "relates/3 requires both nodes to exist, but #{inspect(id)} does not"
    end

    planner
  end

  # ============================================================================
  # Protocol implementations
  # ============================================================================

  defimpl Choreo.Viewable do
    def rebuild(planner, new_graph) do
      existing_ids = MapSet.new(Map.keys(new_graph.edges))

      new_meta =
        Enum.reduce(Map.keys(planner.edge_meta), %{}, fn eid, acc ->
          if eid in existing_ids, do: Map.put(acc, eid, planner.edge_meta[eid]), else: acc
        end)

      %{planner | graph: new_graph, edge_meta: new_meta}
    end

    def zoom_predicate(_, _), do: fn _id, _data -> true end
    def virtual_edge_meta(_), do: %{type: :virtual}
  end

  defimpl Choreo.DOT do
    def to_dot(planner, opts), do: Choreo.Planner.Render.DOT.to_dot(planner, opts)
  end

  defimpl Choreo.Mermaid do
    def to_mermaid(planner, opts), do: Choreo.Planner.Render.Mermaid.to_mermaid(planner, opts)
  end
end
