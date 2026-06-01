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
  """

  @type table_id :: Yog.node_id()
  @type t :: %__MODULE__{
          graph: Yog.Multi.graph(),
          edge_meta: %{optional(Yog.Multi.edge_id()) => map()}
        }

  defstruct graph: nil, edge_meta: %{}

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
    ]
  ]

  @doc """
  Initializes a new, empty ERD.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      graph: Yog.Multi.new(:directed),
      edge_meta: %{}
    }
  end

  @doc """
  Adds a table to the ERD diagram with structured columns.

  ## Options
  #{NimbleOptions.docs(@add_table_schema)}
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
  """
  @spec add_relationship(t(), table_id(), table_id(), keyword()) :: t()
  def add_relationship(%__MODULE__{} = erd, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_relationship_schema)

    # Validate that both tables exist in the graph
    if not Map.has_key?(erd.graph.nodes, from) do
      raise ArgumentError, "table #{inspect(from)} does not exist in the diagram"
    end

    if not Map.has_key?(erd.graph.nodes, to) do
      raise ArgumentError, "table #{inspect(to)} does not exist in the diagram"
    end

    meta = Map.new(opts)

    {graph, edge_id} = Yog.Multi.add_edge(erd.graph, from, to, 1)
    edge_meta = Map.put(erd.edge_meta, edge_id, meta)

    %{erd | graph: graph, edge_meta: edge_meta}
  end

  @doc """
  Renders the ERD to Graphviz DOT syntax.
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = erd, opts \\ []) do
    Choreo.ERD.Render.DOT.to_dot(erd, opts)
  end

  @doc """
  Renders the ERD to Mermaid.js native erDiagram syntax.
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = erd, opts \\ []) do
    Choreo.ERD.Render.Mermaid.to_mermaid(erd, opts)
  end

  @doc """
  Returns a theme for the ERD diagram.
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
