defmodule Choreo.ERD do
  @moduledoc """
  Entity-Relationship Diagram (ERD) builder on top of Yog.

  `Choreo.ERD` models database schemas, including tables, primary/foreign keys,
  column definitions, and relations with standard cardinalities.

  ## Node types
  * `:table` — represents a database table with structured columns.

  ## Edge types
  * Relationships model foreign key links with standard multiplicities:
    * `:one_to_one` (exactly-one to exactly-one)
    * `:one_to_many` (exactly-one to zero-or-more)
    * `:zero_or_one_to_many` (zero-or-one to zero-or-more)
    * `:exactly_one_to_many` (exactly-one to one-or-more)
    * `:many_to_many` (zero-or-more to zero-or-more)

  ## Quick Start

      erd =
        Choreo.ERD.new()
        |> Choreo.ERD.add_table(:users, columns: [
          %{name: :id, type: :integer, key: :pk},
          %{name: :email, type: :varchar}
        ])
        |> Choreo.ERD.add_table(:posts, columns: [
          %{name: :id, type: :integer, key: :pk},
          %{name: :user_id, type: :integer, key: :fk},
          %{name: :title, type: :varchar}
        ])
        |> Choreo.ERD.add_relationship(:users, :posts, cardinality: :one_to_many, label: "writes")

      dot = Choreo.ERD.to_dot(erd)
      mermaid = Choreo.ERD.to_mermaid(erd)

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=1.2, ranksep=1.2];
      node [shape=plain, style=filled, fillcolor="transparent", fontname="Helvetica", fontsize=12, fontcolor="#1e293b"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      users [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="6" COLOR="#cbd5e1"><TR><TD COLSPAN="3" BGCOLOR="#3b82f6" ALIGN="CENTER" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#ffffff"><B>users</B></FONT></TD></TR><TR><TD ALIGN="LEFT" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b">id</FONT></TD><TD ALIGN="LEFT" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b"><i>integer</i></FONT></TD><TD ALIGN="CENTER" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b"><b>[PK]</b></FONT></TD></TR><TR><TD ALIGN="LEFT" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b">email</FONT></TD><TD ALIGN="LEFT" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b"><i>varchar</i></FONT></TD><TD ALIGN="CENTER" BORDER="1" COLOR="#cbd5e1"></TD></TR></TABLE>>];
      posts [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="6" COLOR="#cbd5e1"><TR><TD COLSPAN="3" BGCOLOR="#3b82f6" ALIGN="CENTER" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#ffffff"><B>posts</B></FONT></TD></TR><TR><TD ALIGN="LEFT" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b">id</FONT></TD><TD ALIGN="LEFT" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b"><i>integer</i></FONT></TD><TD ALIGN="CENTER" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b"><b>[PK]</b></FONT></TD></TR><TR><TD ALIGN="LEFT" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b">user_id</FONT></TD><TD ALIGN="LEFT" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b"><i>integer</i></FONT></TD><TD ALIGN="CENTER" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b"><i>[FK]</i></FONT></TD></TR><TR><TD ALIGN="LEFT" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b">title</FONT></TD><TD ALIGN="LEFT" BORDER="1" COLOR="#cbd5e1"><FONT COLOR="#1e293b"><i>varchar</i></FONT></TD><TD ALIGN="CENTER" BORDER="1" COLOR="#cbd5e1"></TD></TR></TABLE>>];

      users -> posts [penwidth="1.0", color="#64748b", dir="both", arrowhead="crowodot", arrowtail="teetee", label="writes"];
    }
  </div>
  """

  @type table_id :: Yog.node_id()
  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          strict_column_matching: boolean()
        }

  defstruct graph: nil, edge_meta: %{}, strict_column_matching: false

  @column_schema [
    name: [
      type: :any,
      required: true,
      doc: "The name of the column (atom or string)."
    ],
    type: [
      type: :any,
      required: true,
      doc: "The data type of the column (e.g. :integer, :varchar)."
    ],
    key: [
      type: {:in, [:pk, :fk, nil]},
      required: false,
      doc: "Key constraint: :pk (primary key), :fk (foreign key), or nil."
    ],
    comment: [
      type: :string,
      required: false,
      doc: "Optional comment describing the column."
    ]
  ]

  @add_table_schema [
    label: [
      type: :string,
      required: false,
      doc: "Visual label for the table. Defaults to stringified table ID."
    ],
    columns: [
      type: :any,
      required: true,
      doc: "List of structured columns."
    ]
  ]

  @cardinalities [
    :one_to_one,
    :one_to_many,
    :zero_or_one_to_many,
    :exactly_one_to_many,
    :many_to_many
  ]

  @add_relationship_schema [
    label: [
      type: :string,
      required: false,
      doc: "Visual label/description of the relationship (e.g. 'writes')."
    ],
    cardinality: [
      type: {:in, @cardinalities},
      required: true,
      doc:
        "Multiplicity constraint: :one_to_one, :one_to_many, :zero_or_one_to_many, :exactly_one_to_many, or :many_to_many."
    ],
    from_column: [
      type: :any,
      required: false,
      doc: "The name of the column in the source table (atom or string)."
    ],
    to_column: [
      type: :any,
      required: false,
      doc: "The name of the column in the destination table (atom or string)."
    ]
  ]

  @doc """
  Initializes a new, empty ERD.

  ## Options

    * `:strict_column_matching` - if `true`, validates that any foreign key columns mapped between tables exist and have matching types (default: `false`).

  ## Examples

      iex> erd = Choreo.ERD.new()
      iex> %Choreo.ERD{} = erd
      iex> erd.strict_column_matching
      false
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    strict = Keyword.get(opts, :strict_column_matching, false)

    %__MODULE__{
      graph: Yog.Multi.new(:directed),
      edge_meta: %{},
      strict_column_matching: strict
    }
  end

  @doc """
  Adds a table to the ERD diagram with structured columns.

  ## Options
  #{NimbleOptions.docs(@add_table_schema)}

  ## Examples

      iex> erd = Choreo.ERD.new()
      ...> |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer, key: :pk}])
      iex> %Choreo.ERD{} = erd
      iex> Map.has_key?(erd.graph.nodes, :users)
      true
  """
  @spec add_table(t(), table_id(), keyword()) :: t()
  def add_table(%__MODULE__{} = erd, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_table_schema)
    columns = opts[:columns]

    if not is_list(columns) do
      raise ArgumentError, "expected :columns to be a list"
    end

    validated_columns =
      Enum.map(columns, fn col ->
        NimbleOptions.validate!(Keyword.new(col), @column_schema)
      end)

    data = %{
      type: :table,
      label: Keyword.get(opts, :label, to_string(id)),
      columns: validated_columns
    }

    %{erd | graph: Yog.Multi.add_node(erd.graph, id, data)}
  end

  @doc """
  Adds a directed relationship/foreign key edge between two tables in the ERD.

  ## Options
  #{NimbleOptions.docs(@add_relationship_schema)}

  ## Examples

      iex> erd = Choreo.ERD.new()
      ...> |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      ...> |> Choreo.ERD.add_table(:posts, columns: [%{name: :user_id, type: :integer}])
      ...> |> Choreo.ERD.add_relationship(:users, :posts, cardinality: :one_to_many)
      iex> %Choreo.ERD{} = erd
      iex> map_size(erd.graph.edges)
      1
  """
  @spec add_relationship(t(), table_id(), table_id(), keyword()) :: t()
  def add_relationship(%__MODULE__{} = erd, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_relationship_schema)

    erd =
      if Map.has_key?(erd.graph.nodes, from) do
        erd
      else
        add_table(erd, from, columns: [], label: to_string(from))
      end

    erd =
      if Map.has_key?(erd.graph.nodes, to) do
        erd
      else
        add_table(erd, to, columns: [], label: to_string(to))
      end

    if erd.strict_column_matching do
      if is_nil(opts[:from_column]) or is_nil(opts[:to_column]) do
        raise ArgumentError,
              "strict_column_matching is enabled; both :from_column and :to_column must be provided"
      end
    end

    from_col_name = opts[:from_column]
    to_col_name = opts[:to_column]

    if from_col_name && to_col_name do
      from_data = Map.get(erd.graph.nodes, from)
      to_data = Map.get(erd.graph.nodes, to)

      from_col =
        Enum.find(from_data[:columns], fn col ->
          to_string(col[:name]) == to_string(from_col_name)
        end)

      to_col =
        Enum.find(to_data[:columns], fn col ->
          to_string(col[:name]) == to_string(to_col_name)
        end)

      if is_nil(from_col) do
        raise ArgumentError,
              "column #{inspect(from_col_name)} does not exist in table #{inspect(from)}"
      end

      if is_nil(to_col) do
        raise ArgumentError,
              "column #{inspect(to_col_name)} does not exist in table #{inspect(to)}"
      end

      if to_string(from_col[:type]) != to_string(to_col[:type]) do
        raise ArgumentError,
              "type mismatch: column #{inspect(from_col_name)} in table #{inspect(from)} has type #{inspect(from_col[:type])}, but column #{inspect(to_col_name)} in table #{inspect(to)} has type #{inspect(to_col[:type])}"
      end
    end

    meta = Map.new(opts)

    {graph, edge_id} = Yog.Multi.add_edge(erd.graph, from, to, 1)
    edge_meta = Map.put(erd.edge_meta, edge_id, meta)

    %{erd | graph: graph, edge_meta: edge_meta}
  end

  @doc """
  Renders the ERD to Graphviz DOT syntax.

  ## Examples

      iex> erd = Choreo.ERD.new() |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      iex> dot = Choreo.ERD.to_dot(erd)
      iex> dot =~ "digraph"
      true
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = erd, opts \\ []) do
    Choreo.ERD.Render.DOT.to_dot(erd, opts)
  end

  @doc """
  Renders the ERD to Mermaid.js native erDiagram syntax.

  ## Examples

      iex> erd = Choreo.ERD.new() |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])
      iex> Choreo.ERD.to_mermaid(erd) =~ "erDiagram"
      true
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = erd, opts \\ []) do
    Choreo.ERD.Render.Mermaid.to_mermaid(erd, opts)
  end

  @doc """
  Returns a theme for the ERD diagram.

  ## Examples

      iex> theme = Choreo.ERD.theme(:dark)
      iex> theme.graph_bgcolor
      "#0f172a"
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.ERD.Render.DOT.theme(name, overrides)
  end
end

defimpl Choreo.DOT, for: Choreo.ERD do
  def to_dot(erd, opts), do: Choreo.ERD.Render.DOT.to_dot(erd, opts)
end

defimpl Choreo.Mermaid, for: Choreo.ERD do
  def to_mermaid(erd, opts), do: Choreo.ERD.Render.Mermaid.to_mermaid(erd, opts)
end

defimpl Choreo.Viewable, for: Choreo.ERD do
  def rebuild(erd, new_graph) do
    edge_ids = Map.keys(new_graph.edges)
    edge_meta = Map.take(erd.edge_meta, edge_ids)

    edge_meta =
      Enum.reduce(edge_ids, edge_meta, fn edge_id, acc ->
        if Map.has_key?(acc, edge_id) do
          acc
        else
          Map.put(acc, edge_id, virtual_edge_meta(erd))
        end
      end)

    %Choreo.ERD{erd | graph: new_graph, edge_meta: edge_meta}
  end

  def zoom_predicate(_erd, _level) do
    fn _data -> true end
  end

  def virtual_edge_meta(_erd) do
    %{
      type: :uses,
      cardinality: :one_to_many,
      label: "virtual"
    }
  end
end
