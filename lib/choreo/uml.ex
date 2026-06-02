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
  """

  @type class_id :: Yog.node_id()
  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          strict_contract_validation: boolean()
        }

  defstruct graph: nil, edge_meta: %{}, strict_contract_validation: false

  @field_schema [
    name: [
      type: :any,
      required: true,
      doc: "The name of the attribute/field."
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
      type: :any,
      required: true,
      doc: "The name of the function."
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
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    strict = Keyword.get(opts, :strict_contract_validation, false)

    %__MODULE__{
      graph: Yog.Multi.new(:directed),
      edge_meta: %{},
      strict_contract_validation: strict
    }
  end

  @doc """
  Adds a class, struct, behavior, or protocol to the diagram.
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
        NimbleOptions.validate!(Keyword.new(f), @field_schema)
      end)

    validated_functions =
      Enum.map(functions, fn func ->
        NimbleOptions.validate!(Keyword.new(func), @function_schema)
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
  """
  @spec add_relationship(t(), class_id(), class_id(), keyword()) :: t()
  def add_relationship(%__MODULE__{} = uml, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_relationship_schema)

    # Validate that both classes exist in the graph
    if not Map.has_key?(uml.graph.nodes, from) do
      raise ArgumentError, "class #{inspect(from)} does not exist in the diagram"
    end

    if not Map.has_key?(uml.graph.nodes, to) do
      raise ArgumentError, "class #{inspect(to)} does not exist in the diagram"
    end

    meta = Map.new(opts)

    if uml.strict_contract_validation and meta[:type] in [:realizes, :inherits] do
      from_node = Map.get(uml.graph.nodes, from)
      to_node = Map.get(uml.graph.nodes, to)

      if to_node[:type] in [:behavior, :protocol, :interface] do
        target_funcs = to_node[:functions] || []
        source_funcs = from_node[:functions] || []

        missing =
          Enum.filter(target_funcs, fn tf ->
            not Enum.any?(source_funcs, fn sf ->
              sf[:name] == tf[:name] and (is_nil(tf[:arity]) or sf[:arity] == tf[:arity])
            end)
          end)

        if missing != [] do
          missing_strs =
            Enum.map_join(missing, ", ", fn f ->
              "#{f[:name]}/#{f[:arity] || "any"}"
            end)

          raise ArgumentError,
                "contract violation: class #{inspect(from)} does not implement required functions from #{inspect(to)}: #{missing_strs}"
        end
      end
    end

    {graph, edge_id} = Yog.Multi.add_edge(uml.graph, from, to, 1)
    edge_meta = Map.put(uml.edge_meta, edge_id, meta)

    %{uml | graph: graph, edge_meta: edge_meta}
  end

  @doc """
  Renders the UML diagram to Graphviz DOT syntax.
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = uml, opts \\ []) do
    Choreo.UML.Render.DOT.to_dot(uml, opts)
  end

  @doc """
  Renders the UML diagram to Mermaid.js syntax.
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = uml, opts \\ []) do
    Choreo.UML.Render.Mermaid.to_mermaid(uml, opts)
  end

  @doc """
  Returns a theme for the UML diagram.
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

  def zoom_predicate(_uml, _level) do
    fn _data -> true end
  end

  def virtual_edge_meta(_uml) do
    %{
      type: :depends,
      label: "virtual"
    }
  end
end
