# Lab DSL + Compose/View Cheatsheet

A fast reference for sketching diagrams with `Choreo.Lab.DSL.*`, combining them with `Choreo.Lab.Compose`, and exploring them with `Choreo.Lab.View`.

For complete explanations, see [`lab_dsl.md`](lab_dsl.md).

## Mental model

```text
Lab DSLs create models.
Lab Compose combines models.
Lab View explores models.
Renderers present models.
Analysis remains explicit.
```

## Universal DSL shape

```elixir
alias Choreo.Lab.DSL.C4, as: C4DSL

model =
  C4DSL.c4 do
    a = noun("A")
    b = noun("B")

    a ~> b
    a ~> b |> verb("meaning")
    edge a ~> b, "label"
    verb a ~> b, "label"
  end
```

Use the actual noun and verb vocabulary for the diagram type, for example:

```elixir
customer = person("Customer")
api = container("API")
db = container("Database")

customer ~> api |> uses("HTTPS")
api ~> db |> reads("SQL")
```

## Identity rule

```text
id: option > variable name > slugged label
```

```elixir
api = service("Gateway API")
# graph id: :api
# display label/name: "Gateway API"

service("Gateway API")
# graph id: :gateway_api
# display label/name: "Gateway API"

service("Gateway API", id: :api_gateway)
# graph id: :api_gateway
# display label/name: "Gateway API"
```

Requirement DSL exception:

```elixir
functional("Users must authenticate with MFA", id: "REQ-001", node_id: :mfa)
```

`id:` is the human requirement ID. `node_id:` is the graph node ID.

## Edge forms

```elixir
# Plain relationship
api ~> db

# Pipe modifier relationship
api ~> db |> reads("tenant config")

# Explicit edge with label
edge api ~> db, "tenant config"

# Explicit edge with options
edge api ~> db, label: "tenant config", technology: "SQL"

# Typed edge constructor
reads api ~> db, "tenant config", technology: "SQL"
```

## Discovery

```elixir
Choreo.Lab.DSL.C4.taxonomy()
Choreo.Lab.DSL.Dataflow.taxonomy()
Choreo.Lab.DSL.Workflow.taxonomy()
```

`verbs/0` is a compatibility alias for `taxonomy/0`.

## Diagram nouns and verbs

The **nouns** column lists node constructors. The **verbs** column lists typed edge constructors. Every DSL also supports `~>` shape; many support generic `edge`, `on`, and `label` forms.

| Diagram | Entry macro | Nouns | Verbs |
| --- | --- | --- | --- |
| C4 | `c4` | `person`, `system`, `container`, `component`, `database`, `service` | `uses`, `calls`, `sends`, `publishes`, `consumes`, `reads`, `writes`, `routes`, `depends` |
| Dataflow | `dataflow` | `source`, `transform`, `buffer`, `conditional`, `merge`, `sink`, `queue`, `topic` | `emits`, `sends`, `publishes`, `consumes`, `reads`, `writes`, `routes`, `normal`, `error`, `retry`, `dead_letter` |
| Decision tree | `decision_tree` | `root`, `decision`, `question`, `outcome`, `result`, `leaf` | `branch` |
| Dependency | `dependency` | `application`, `service`, `library`, `package`, `module`, `component`, `interface`, `test_suite` | `depends_on`, `uses`, `imports`, `calls`, `inherits`, `implements`, `dev` |
| Domain | `domain` | `bounded_context`, `actor`, `command`, `aggregate`, `entity`, `event`, `read_model`, `policy`, `saga`, `external_system`, `acl` | `initiates`, `handles`, `emits`, `triggers`, `projects_to`, `notifies`, `translates_via`, `shared_kernel`, `customer_supplier`, `conformist`, `anti_corruption` |
| ERD | `erd` | `table`, `entity`; columns: `pk`, `field`, `fk` | `one_to_one`, `one_to_many`, `zero_or_one_to_many`, `exactly_one_to_many`, `many_to_many`, `has_one`, `has_many` |
| FSM | `fsm` | `state`, `initial`, `final` | `~>`, `edge`; modifiers: `on`, `label`, `guard` |
| Infrastructure | `infrastructure` | `user`, `client`, `gateway`, `load_balancer`, `service`, `compute`, `database`, `cache`, `queue`, `storage`, `internet`, `network`, `external` | `~>`, `edge`; modifiers: `on`, `label` |
| Mind map | `mind_map` | `root`, `topic`, `subtopic`, `note` | `branch`, `associate`, `association` |
| Planner | `planner` | `task`, `story`, `bug`, `milestone`, `phase`, `owner`, `label` | `depends_on`, `blocks`, `contains`, `assigned_to`, `tagged_with`, `relates_to` |
| Requirement | `requirements` | `requirement`, `functional`, `performance`, `constraint`, `component`, `service`, `test_case`, `stakeholder`, `owner` | `satisfies`, `verifies`, `refines`, `depends`, `traces`, `contains`, `derives`, `relates` |
| Sequence | `sequence` | `actor`, `participant`, `service`, `system`, `user` | `message`, `call`, `request`, `sync`, `async`, `signal`, `publish`, `reply`, `return`, `response` |
| Threat model | `threat_model` | `external_entity`, `process`, `data_store`, `actor`, `service`, `api`, `worker`, `database`, `cache`, `queue` | `flow`, `data_flow`, `sends`, `reads`, `writes`, `encrypted`, `unencrypted` |
| UML | `uml` | `class`, `struct`, `behavior`, `protocol`, `interface` | `inherits`, `extends`, `realizes`, `implements`, `associates`, `has`, `depends`, `uses` |
| Workflow | `workflow` | `begin`, `task`, `decision`, `fork`, `join`, `compensation`, `event`, `finish`, `swimlane` | `sequence`, `then`, `compensation`, `retry`, `failure`, `timeout`, `error` |

## Copy-paste mini examples

### C4

```elixir
alias Choreo.Lab.DSL.C4, as: C4DSL

architecture =
  C4DSL.c4 do
    user = person("User")
    api = container("API", technology: "Phoenix")
    db = container("Database", technology: "Postgres")

    user ~> api |> uses("HTTPS")
    api ~> db |> reads("SQL")
  end
```

### Dataflow

```elixir
alias Choreo.Lab.DSL.Dataflow, as: DataflowDSL

pipeline =
  DataflowDSL.dataflow do
    kafka = source("Kafka")
    parser = transform("Parser")
    warehouse = sink("Warehouse")
    dlq = sink("Dead Letter Queue")

    kafka ~> parser |> emits("events")
    parser ~> warehouse |> writes("rows")
    error parser ~> dlq, "invalid events"
  end
```

### Workflow

```elixir
alias Choreo.Lab.DSL.Workflow, as: WorkflowDSL

flow =
  WorkflowDSL.workflow do
    start = begin("Request received")
    validate = task("Validate token")
    authorized = decision("Authorized?")
    accepted = finish("Return 200")
    rejected = finish("Return 403")

    start ~> validate
    validate ~> authorized
    authorized ~> accepted |> condition("yes")
    failure authorized ~> rejected, "no"
  end
```

### Domain

```elixir
alias Choreo.Lab.DSL.Domain, as: DomainDSL

domain_model =
  DomainDSL.domain do
    customer = actor("Customer")
    place_order = command("Place Order")
    order = aggregate("Order")
    placed = event("Order Placed")
    summary = read_model("Order Summary")

    customer ~> place_order |> initiates("starts")
    place_order ~> order |> handles("validates")
    order ~> placed |> emits("records")
    placed ~> summary |> projects_to("updates")
  end
```

### Requirement traceability

```elixir
alias Choreo.Lab.DSL.Requirement, as: RequirementDSL

traceability =
  RequirementDSL.requirements "Auth v2" do
    security = stakeholder("Security Team")
    mfa = functional("Users must authenticate with MFA", id: "REQ-001")
    auth = component("Auth Service")
    test = test_case("MFA login test")

    security ~> mfa |> traces("owns")
    auth ~> mfa |> satisfies("implements")
    test ~> mfa |> verifies("proves")
  end
```

## Nested blocks

Some DSLs support nested blocks for visual hierarchy or inherited scope.

```elixir
C4DSL.c4 do
  system("Banking", scope: :in) do
    api = container("API")
    db = container("Database")

    api ~> db |> reads("SQL")
  end
end
```

```elixir
WorkflowDSL.workflow do
  swimlane("Backend") do
    start = begin("Request received")
    validate = task("Validate token")
    done = finish("Return 200")

    start ~> validate
    validate ~> done
  end
end
```

```elixir
DomainDSL.domain do
  context_boundary("Checkout") do
    customer = actor("Customer")
    place_order = command("Place Order")
    order = aggregate("Order")

    customer ~> place_order |> initiates("starts")
    place_order ~> order |> handles("validates")
  end
end
```

## Compose cheatsheet

`Choreo.Lab.Compose` combines multiple models into one larger graph.

```elixir
alias Choreo.Lab.Compose

combined =
  Choreo.new()
  |> Compose.cluster(:architecture, label: "Architecture")
  |> Compose.cluster(:auth, label: "Auth Flow")
  |> Compose.embed(architecture, into: :architecture, as: :c4)
  |> Compose.embed(auth_flow, into: :auth, as: :auth)
  |> Compose.connect(:c4_api, :auth_idle, "uses auth state machine")
  |> Compose.trace(:c4_api, :auth_authenticated, :runtime)
```

### Compose helpers

| Helper | Use |
| --- | --- |
| `Compose.cluster(system, id, opts \\ [])` | Add a cluster/group to a combined graph. |
| `Compose.embed(system, child, into: cluster, as: prefix)` | Embed another Choreo model into a cluster with prefixed node IDs. |
| `Compose.connect(system, from, to, label_or_opts \\ [])` | Connect two nodes across embedded models. |
| `Compose.trace(system, from, to, type_or_opts \\ [])` | Add a traceability relationship between nodes. |

### Embed ID rule

When embedding with `as: :c4`, child node IDs are prefixed:

```elixir
:c4_api
:c4_db
:c4_customer
```

Use those prefixed IDs in `Compose.connect/4`, `Compose.trace/4`, and `View` helpers.

## View cheatsheet

`Choreo.Lab.View` explores, filters, and renders models without changing the original modeling intent.

```elixir
alias Choreo.Lab.View

focused = View.focus(combined, :c4_api)
trace = View.trace(combined, :c4_api, :auth_authenticated)
path = View.path(combined, :c4_customer, :c4_db)
zoomed = View.zoom(combined, 2)
```

### View helpers

| Helper | Use |
| --- | --- |
| `View.zoom(diagram, level, opts \\ [])` | Show a diagram at a given abstraction/detail level. |
| `View.focus(diagram, node, opts \\ [])` | Focus around one node. |
| `View.path(diagram, from, to, opts \\ [])` | Focus the path between two nodes. |
| `View.trace(diagram, from, to, opts \\ [])` | Focus a trace between two nodes. |
| `View.collapse_nodes(diagram, ids, new_id, opts \\ [])` | Collapse selected nodes into one node. |
| `View.collapse_type(diagram, types, new_id, opts \\ [])` | Collapse nodes by node type. |
| `View.tabs(diagram, opts \\ [])` | Render Livebook tabs with available diagram views. |
| `View.to_siren(diagram, opts \\ [])` | Render Mermaid with `Choreo.Lab.Siren`. |
| `View.to_sketch(diagram, opts \\ [])` | Render Mermaid with `Choreo.Lab.Sketch`. |
| `View.to_mermaid(diagram, opts \\ [])` | Return Mermaid source. |
| `View.to_dot(diagram, opts \\ [])` | Return Graphviz DOT source. |

## Livebook render shortcuts

```elixir
alias Choreo.Lab.View

View.tabs(architecture)
View.to_siren(architecture)
View.to_sketch(architecture)

mermaid = View.to_mermaid(architecture)
dot = View.to_dot(architecture)
```

For explicit tabs:

```elixir
mermaid = Choreo.to_mermaid(architecture)
dot = Choreo.to_dot(architecture)

Kino.Layout.tabs(
  Siren: Choreo.Lab.Siren.new(mermaid),
  Graphviz: Kino.VizJS.render(dot, height: 500),
  Sketch: Choreo.Lab.Sketch.new(mermaid)
)
```

## `.choreo.exs` render workflow

```elixir
# diagrams/system.choreo.exs
alias Choreo.Lab.DSL.C4, as: C4DSL

C4DSL.c4 do
  user = person("User")
  api = container("API")

  user ~> api |> uses("HTTPS")
end
```

```sh
mix choreo.render diagrams/system.choreo.exs --out diagrams/system.mmd
mix choreo.render diagrams/system.choreo.exs --to dot --out diagrams/system.dot
```

Multi-artifact files can return a map:

```elixir
%{
  architecture: architecture,
  pipeline: pipeline,
  workflow: flow
}
```

```sh
mix choreo.render diagrams/system.choreo.exs --out priv/diagrams/
```

## Style reminders

- Prefer variable-bound nodes in examples: `api = container("API")`.
- Prefer canonical nouns in docs: `container`, `aggregate`, `data_store`, `task`, `table`.
- Label relationships with verbs: `"Reads from"`, `"Publishes"`, `"Authenticates via"`.
- Use aliases like `db`, `dlq`, `app`, or `done` for fast sketches, not canonical docs.
- Use `taxonomy/0` when in doubt.
- Use the stable pipe API for production/library code and dynamic model construction.
