defmodule Choreo.UML do
  @moduledoc """
  UML Class and Struct Diagram builder on top of Yog.

  `Choreo.UML` models software component architectures — classes, structs,
  behaviors, protocols, and interfaces — with fields and functions, and
  standard structural UML relationships.

  ## Node types
  * `:class` / `:struct` / `:behavior` / `:protocol` / `:interface`

  ## Relationship types
  * `:inherits` — solid line with hollow arrowhead (`--|>`) representing inheritance or behavior adoption.
  * `:realizes` — dashed line with hollow arrowhead (`..|>`) representing protocol implementation.
  * `:associates` — solid line with solid arrowhead (`-->`) representing composition or nesting.
  * `:depends` — dashed line with open arrowhead (`..>`) representing invocation or dependency.

  ## Quick Start

      uml =
        Choreo.UML.new()
        |> Choreo.UML.add_class(:user,
          type: :struct,
          fields: [%{name: :id, type: :integer}],
          functions: [%{name: "authenticate", arity: 1}]
        )
        |> Choreo.UML.add_class(:auth_provider,
          type: :behavior,
          functions: [%{name: "verify", arity: 1}]
        )
        |> Choreo.UML.add_relationship(:user, :auth_provider, type: :realizes, label: "implements")

      dot = Choreo.UML.to_dot(uml)
      mermaid = Choreo.UML.to_mermaid(uml)

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, bgcolor="#ffffff", splines=spline, nodesep=1.2, ranksep=1.2];
      node [shape=plain, style=filled, fillcolor="transparent", fontname="Helvetica", fontsize=11, fontcolor="#1e293b"];
      edge [color="#475569", style=solid, fontname="Helvetica", fontsize=9, penwidth=1.0];

      user [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="4" PORT="f0" COLOR="#cbd5e1"><TR><TD BGCOLOR="#10b981"><FONT COLOR="#ffffff"><B>«struct»<BR/>user</B></FONT></TD></TR><TR><TD BGCOLOR="#f8fafc" ALIGN="LEFT"><FONT COLOR="#1e293b">+ id : integer</FONT></TD></TR><TR><TD BGCOLOR="#f8fafc" ALIGN="LEFT"><FONT COLOR="#1e293b">+ authenticate(1)</FONT></TD></TR></TABLE>>];
      auth_provider [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="4" PORT="f0" COLOR="#cbd5e1"><TR><TD BGCOLOR="#f59e0b"><FONT COLOR="#ffffff"><B>«behavior»<BR/>auth_provider</B></FONT></TD></TR><TR><TD BGCOLOR="#f8fafc" HEIGHT="10"></TD></TR><TR><TD BGCOLOR="#f8fafc" ALIGN="LEFT"><FONT COLOR="#1e293b">+ verify(1)</FONT></TD></TR></TABLE>>];

      user -> auth_provider [penwidth="1.0", color="#475569", arrowhead="empty", style="dashed", fontsize="9", fontname="Helvetica", label="implements"];
    }
  </div>
  """

  @type class_id :: Yog.node_id()
  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          strict_contract_validation: boolean(),
          strict: boolean()
        }

  defstruct graph: nil, edge_meta: %{}, strict_contract_validation: false, strict: false

  @field_schema [
    name: [
      type: {:or, [:atom, :string]},
      required: true,
      doc: "The name of the attribute/field (atom or string)."
    ],
    type: [
      type: :any,
      required: false,
      doc: "The type of the field."
    ],
    visibility: [
      type: {:in, [:public, :private, :protected, nil]},
      required: false,
      default: :public,
      doc: "The visibility: :public, :private, :protected, or nil."
    ]
  ]

  @function_schema [
    name: [
      type: {:or, [:atom, :string]},
      required: true,
      doc: "The name of the function (atom or string)."
    ],
    arity: [
      type: :integer,
      required: false,
      doc: "The arity of the function."
    ],
    return: [
      type: :any,
      required: false,
      doc: "The return type of the function."
    ],
    visibility: [
      type: {:in, [:public, :private, :protected, nil]},
      required: false,
      default: :public,
      doc: "The visibility of the function."
    ]
  ]

  @add_class_schema [
    label: [
      type: :string,
      required: false,
      doc: "Visual label for the class (defaults to ID string)."
    ],
    type: [
      type: {:in, [:class, :struct, :behavior, :protocol, :interface]},
      required: false,
      default: :class,
      doc: "The UML class type: :class, :struct, :behavior, :protocol, or :interface."
    ],
    fields: [
      type: :any,
      required: false,
      default: [],
      doc: "List of fields/attributes."
    ],
    functions: [
      type: :any,
      required: false,
      default: [],
      doc: "List of functions/operations."
    ]
  ]

  @add_relationship_schema [
    type: [
      type: {:in, [:inherits, :realizes, :associates, :depends]},
      required: true,
      doc: "The connection relationship type."
    ],
    label: [
      type: :string,
      required: false,
      doc: "Optional label/text on the relationship line."
    ]
  ]

  @doc """
  Initializes a new, empty UML diagram.

  ## Options

    * `:strict_contract_validation` - if `true`, validates that any class implementing a behavior/protocol/interface implements all its required functions (default: `false`).
    * `:strict` - if `true`, `add_relationship/4` raises when an endpoint does not already exist (default: `false`).

  ## Examples

      iex> uml = Choreo.UML.new()
      iex> %Choreo.UML{} = uml
      iex> uml.strict_contract_validation
      false
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      graph: Yog.Multi.new(:directed),
      edge_meta: %{},
      strict_contract_validation: Keyword.get(opts, :strict_contract_validation, false),
      strict: Keyword.get(opts, :strict, false)
    }
  end

  @doc """
  Adds a class, struct, behavior, or protocol to the diagram.

  ## Options

  #{NimbleOptions.docs(@add_class_schema)}

  ## Examples

      iex> uml = Choreo.UML.new()
      ...> |> Choreo.UML.add_class(:user, type: :struct, fields: [%{name: :id, type: :integer}])
      iex> %Choreo.UML{} = uml
      iex> Map.has_key?(uml.graph.nodes, :user)
      true
  """
  @spec add_class(t(), class_id(), keyword()) :: t()
  def add_class(%__MODULE__{} = uml, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_class_schema)
    fields = opts[:fields] || []
    functions = opts[:functions] || []

    if not is_list(fields) do
      raise ArgumentError, "expected :fields to be a list"
    end

    if not is_list(functions) do
      raise ArgumentError, "expected :functions to be a list"
    end

    validated_fields =
      Enum.map(fields, fn f ->
        validated = NimbleOptions.validate!(Keyword.new(f), @field_schema)
        Keyword.update!(validated, :name, &to_string/1)
      end)

    validated_functions =
      Enum.map(functions, fn func ->
        validated = NimbleOptions.validate!(Keyword.new(func), @function_schema)
        Keyword.update!(validated, :name, &to_string/1)
      end)

    data = %{
      type: opts[:type] || :class,
      label: Keyword.get(opts, :label, to_string(id)),
      fields: validated_fields,
      functions: validated_functions
    }

    %{uml | graph: Yog.Multi.add_node(uml.graph, id, data)}
  end

  @doc """
  Adds a structural relationship between two classes/components.

  ## Options

  #{NimbleOptions.docs(@add_relationship_schema)}

  ## Examples

      iex> uml = Choreo.UML.new()
      ...> |> Choreo.UML.add_class(:user)
      ...> |> Choreo.UML.add_class(:profile)
      ...> |> Choreo.UML.add_relationship(:user, :profile, type: :associates, label: "has_one")
      iex> %Choreo.UML{} = uml
      iex> map_size(uml.graph.edges)
      1
  """
  @spec add_relationship(t(), class_id(), class_id(), keyword()) :: t()
  def add_relationship(%__MODULE__{} = uml, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_relationship_schema)

    if uml.strict and not Map.has_key?(uml.graph.nodes, from) do
      raise ArgumentError,
            "Source class #{inspect(from)} does not exist (strict mode is enabled)"
    end

    if uml.strict and not Map.has_key?(uml.graph.nodes, to) do
      raise ArgumentError,
            "Target class #{inspect(to)} does not exist (strict mode is enabled)"
    end

    uml =
      if Map.has_key?(uml.graph.nodes, from) do
        uml
      else
        add_class(uml, from, type: :class, label: to_string(from))
      end

    uml =
      if Map.has_key?(uml.graph.nodes, to) do
        uml
      else
        add_class(uml, to, type: :class, label: to_string(to))
      end

    meta = Map.new(opts)

    if uml.strict_contract_validation and meta[:type] in [:realizes, :inherits] do
      case Choreo.Internal.unsatisfied_contract(uml, from, to) do
        [] ->
          :ok

        missing ->
          missing_strs =
            Enum.map_join(missing, ", ", fn f ->
              "#{f[:name]}/#{f[:arity] || "any"}"
            end)

          raise ArgumentError,
                "contract violation: class #{inspect(from)} does not implement required functions from #{inspect(to)}: #{missing_strs}"
      end
    end

    {graph, edge_id} = Yog.Multi.add_edge(uml.graph, from, to, 1)
    edge_meta = Map.put(uml.edge_meta, edge_id, meta)

    %{uml | graph: graph, edge_meta: edge_meta}
  end

  @doc """
  Renders the UML diagram to Graphviz DOT syntax.

  ## Examples

      iex> uml = Choreo.UML.new() |> Choreo.UML.add_class(:user)
      iex> dot = Choreo.UML.to_dot(uml)
      iex> dot =~ "digraph"
      true
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = uml, opts \\ []) do
    Choreo.UML.Render.DOT.to_dot(uml, opts)
  end

  @doc """
  Renders the UML diagram to Mermaid.js syntax.

  ## Examples

      iex> uml = Choreo.UML.new() |> Choreo.UML.add_class(:user)
      iex> Choreo.UML.to_mermaid(uml, syntax: :flowchart) =~ "graph"
      true
      iex> Choreo.UML.to_mermaid(uml, syntax: :class_diagram) =~ "classDiagram"
      true
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = uml, opts \\ []) do
    Choreo.UML.Render.Mermaid.to_mermaid(uml, opts)
  end

  @doc """
  Returns a theme for the UML diagram.

  ## Examples

      iex> theme = Choreo.UML.theme(:dark)
      iex> theme.graph_bgcolor
      "#0f172a"
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.UML.Render.DOT.theme(name, overrides)
  end
end

defimpl Choreo.DOT, for: Choreo.UML do
  def to_dot(uml, opts), do: Choreo.UML.Render.DOT.to_dot(uml, opts)
end

defimpl Choreo.Mermaid, for: Choreo.UML do
  def to_mermaid(uml, opts), do: Choreo.UML.Render.Mermaid.to_mermaid(uml, opts)
end

defimpl Choreo.Viewable, for: Choreo.UML do
  def rebuild(uml, new_graph) do
    edge_ids = Map.keys(new_graph.edges)
    edge_meta = Map.take(uml.edge_meta, edge_ids)

    edge_meta =
      Enum.reduce(edge_ids, edge_meta, fn edge_id, acc ->
        if Map.has_key?(acc, edge_id) do
          acc
        else
          Map.put(acc, edge_id, virtual_edge_meta(uml))
        end
      end)

    %Choreo.UML{uml | graph: new_graph, edge_meta: edge_meta}
  end

  def zoom_predicate(_uml, 0) do
    fn _, d -> d[:type] in [:behavior, :protocol, :interface] end
  end

  def zoom_predicate(_uml, 1) do
    fn _, d -> d[:type] in [:behavior, :protocol, :interface, :class] end
  end

  def zoom_predicate(_uml, _level) do
    fn _, _ -> true end
  end

  def virtual_edge_meta(_uml) do
    %{
      type: :depends,
      label: nil
    }
  end
end
