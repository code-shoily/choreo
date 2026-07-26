# Lab DSLs and Sketch Syntax

Choreo's stable APIs are pipe-first and explicit. The `Choreo.Lab.DSL.*` modules are a lighter sketch layer for Livebook exploration, tutorials, interviews, design reviews, and quick architecture thinking.

Use the Lab DSLs when you want to move quickly from an idea to a model. Use the stable pipe APIs when you want maximum explicitness, dynamic construction, or library/application code.

For a compact reference, see the [Lab DSL + Compose/View Cheatsheet](lab_cheatsheet.md).

## Philosophy

The Lab DSLs follow a small set of rules:

- DSLs compile down to existing stable builders.
- DSLs return ordinary Choreo structs.
- The stable pipe APIs remain canonical.
- Analysis stays explicit; there is no analysis DSL.
- Rendering and styling remain renderer concerns.
- The grammar stays small, strict, and domain-oriented.
- Unknown constructors, unknown variables, and invalid shapes raise instead of silently creating surprising models.

A useful mental model is:

```text
Lab DSLs create models.
Lab Compose combines models.
Lab View explores models.
Renderers present models.
Analysis remains explicit.
```

## Shared grammar

Most Lab DSLs share this visual shape:

```elixir
node = constructor("Label")
other = constructor("Other")

node ~> other
node ~> other |> verb("meaning")
edge node ~> other, "label"
typed_edge node ~> other, "label"
```

The arrow shows graph shape. The pipe modifier carries domain semantics.

Examples across domains:

```elixir
api ~> db |> reads("tenant config")
stream ~> warehouse |> writes("analytics rows")
idle ~> authenticated |> on("valid token")
order ~> order_placed |> emits("records")
auth_service ~> mfa |> satisfies("implements")
```

Prefer variable-bound semantic nodes when labels or metadata matter:

```elixir
api = service("API", technology: "Phoenix")
db = database("Tenant DB", technology: "Postgres")

api ~> db |> reads("tenant configuration", technology: "SQL")
```

Inline constructors are useful for small sketches, but variable-bound nodes make examples easier to extend:

```elixir
person("Customer") ~> system("Banking") |> uses("Uses")
```

## Constructors, edges, and modifiers

DSLs usually support these forms:

```elixir
# Node constructors
api = service("API")
db = database("Postgres", technology: "Postgres")

# Plain edge
api ~> db

# Pipe modifier edge
api ~> db |> reads("queries")

# Explicit edge with label
edge api ~> db, "queries"

# Explicit edge with options
edge api ~> db, label: "queries", technology: "SQL"

# Typed edge constructor
reads api ~> db, "queries", technology: "SQL"
```

Not every DSL supports every exact verb. Use `taxonomy/0` to inspect the current vocabulary.

## Identity rule

Most DSL constructors use this identity rule:

```text
id: option > variable name > slugged label
```

For example:

```elixir
api = service("API")
# id: :api, label/name: "API"

service("API")
# id: :api, label/name: "API"

service("API", id: :gateway)
# id: :gateway, label/name: "API"
```

Some domains have domain-specific identity fields. For example, `Choreo.Lab.DSL.Requirement` uses `id:` for the human requirement ID and `node_id:` when you need to override the graph node ID:

```elixir
req = requirement("Authenticate users", node_id: :authn, id: "REQ-AUTH-001")
```

## Discovery with `taxonomy/0`

Each DSL exposes its vocabulary with `taxonomy/0`:

```elixir
Choreo.Lab.DSL.C4.taxonomy()
Choreo.Lab.DSL.Domain.taxonomy()
Choreo.Lab.DSL.Sequence.taxonomy()
```

This is useful in Livebook when autocomplete is limited. `verbs/0` is kept as a compatibility alias.

A typical taxonomy contains keys such as:

- `:nodes` — node constructors.
- `:edges` — edge constructors and arrow forms.
- `:modifiers` — pipe modifiers for edge metadata.
- `:clusters`, `:swimlanes`, `:tables`, `:columns`, or similar domain-specific groups.
- `:options` — commonly supported option keys.

## Import and alias style

For one diagram, importing the DSL is convenient:

```elixir
import Choreo.Lab.DSL.C4

c4 do
  user = person("User")
  api = container("API")

  user ~> api |> uses("HTTPS")
end
```

For notebooks with multiple diagram types, alias the outer DSL module and call the outer macro with a qualified name:

```elixir
alias Choreo.Lab.DSL.C4, as: C4DSL
alias Choreo.Lab.DSL.ERD, as: ERDDSL

architecture =
  C4DSL.c4 do
    user = person("User")
    api = container("API")

    user ~> api |> uses("HTTPS")
  end

schema =
  ERDDSL.erd do
    users = table("users") do
      pk :id, :uuid
      field :email, :string
    end
  end
```

Only the outer macro needs qualification; the inner sketch syntax remains lightweight.

## Canonical vocabulary style

Many DSLs include aliases for speed and natural sketching. Prefer the canonical vocabulary in guides and shared examples:

- Prefer domain terms over generic aliases: `container`, `aggregate`, `data_store`, `task`, `table`.
- Use edge labels as verbs or short verb phrases: `"Reads from"`, `"Publishes"`, `"Authenticates via"`.
- Prefer pipe modifiers for edge metadata: `api ~> db |> reads("Tenant config")`.
- Use explicit `edge` when a label or option map is clearer than a typed edge.
- Use aliases like `app`, `db`, `dlq`, or `done` for fast sketches, not canonical documentation examples.

## Current DSLs at a glance

| DSL | Entry macro | Returns | Good for |
| --- | --- | --- | --- |
| `Choreo.Lab.DSL.C4` | `c4 do ... end` | `%Choreo.C4{}` | Context, container, and component sketches |
| `Choreo.Lab.DSL.Dataflow` | `dataflow do ... end` | `%Choreo.Dataflow{}` | Sources, transforms, sinks, queues, and error paths |
| `Choreo.Lab.DSL.DecisionTree` | `decision_tree do ... end` | `%Choreo.DecisionTree{}` | Policy/routing decision trees |
| `Choreo.Lab.DSL.Dependency` | `dependency do ... end` | `%Choreo.Dependency{}` | Software dependencies, layers, and coupling |
| `Choreo.Lab.DSL.Domain` | `domain do ... end` | `%Choreo.Domain{}` | DDD, context mapping, event storming, scenarios |
| `Choreo.Lab.DSL.ERD` | `erd do ... end` | `%Choreo.ERD{}` | Tables, columns, keys, and relationships |
| `Choreo.Lab.DSL.FSM` | `fsm do ... end` | `%Choreo.FSM{}` | States and transitions |
| `Choreo.Lab.DSL.Infrastructure` | `infrastructure do ... end` | `%Choreo{}` | Deployment/runtime infrastructure sketches |
| `Choreo.Lab.DSL.MindMap` | `mind_map do ... end` | `%Choreo.MindMap{}` | Brainstorming, outlines, and topic trees |
| `Choreo.Lab.DSL.Planner` | `planner do ... end` | `%Choreo.Planner{}` | Tasks, milestones, owners, labels, and dependencies |
| `Choreo.Lab.DSL.Requirement` | `requirements "Name" do ... end` | `%Choreo.Requirement{}` | Requirement traceability |
| `Choreo.Lab.DSL.Sequence` | `sequence do ... end` | `%Choreo.Sequence{}` | Ordered interactions, messages, notes, fragments |
| `Choreo.Lab.DSL.ThreatModel` | `threat_model do ... end` | `%Choreo.ThreatModel{}` | STRIDE-oriented DFDs and trust boundaries |
| `Choreo.Lab.DSL.UML` | `uml do ... end` | `%Choreo.UML{}` | Class, struct, protocol, and interface sketches |
| `Choreo.Lab.DSL.Workflow` | `workflow do ... end` | `%Choreo.Workflow{}` | Business processes, Sagas, CI/CD, swimlanes |

## Diagram nouns and verbs reference

Use this table as a quick sketching vocabulary reference. The **nouns** column lists node constructors. The **verbs** column lists typed edge constructors; every DSL also supports the basic graph shape with `~>` and many support generic `edge`, `on`, or `label` forms.

| Diagram / DSL | Nouns (node constructors) | Verbs (edge constructors) |
| --- | --- | --- |
| C4 | `person`, `user`, `actor`, `software_system`, `system`, `external_system`, `container`, `application`, `app`, `service`, `database`, `datastore`, `component`, `module` | `relates`, `uses`, `calls`, `sends`, `publishes`, `consumes`, `reads`, `writes`, `routes`, `depends` |
| Dataflow | `source`, `input`, `producer`, `sink`, `output`, `consumer`, `transform`, `process`, `processor`, `buffer`, `queue`, `topic`, `conditional`, `decision`, `split`, `merge`, `join` | `flow`, `flows`, `emits`, `sends`, `publishes`, `consumes`, `reads`, `writes`, `routes`, `normal`, `error`, `retry`, `dead_letter`, `dlq` |
| Decision tree | `root`, `decision`, `question`, `outcome`, `result`, `leaf` | `branch` |
| Dependency | `application`, `app`, `service`, `library`, `lib`, `package`, `dependency`, `module`, `component`, `interface`, `contract`, `protocol`, `test`, `spec`, `test_suite` | `depends`, `depends_on`, `uses`, `imports`, `calls`, `inherits`, `implements`, `dev` |
| Domain | `context`, `bounded_context`, `actor`, `user`, `command`, `aggregate`, `entity`, `event`, `domain_event`, `read_model`, `projection`, `policy`, `saga`, `external_system`, `external`, `type`, `data_type`, `workflow`, `process`, `acl`, `anti_corruption_layer` | `initiates`, `handles`, `emits`, `triggers`, `projects_to`, `notifies`, `translates_via`, `connects`, `shared_kernel`, `customer_supplier`, `conformist`, `open_host_service`, `published_language`, `anti_corruption` |
| ERD | `table`, `entity` | `one_to_one`, `one_to_many`, `zero_or_one_to_many`, `exactly_one_to_many`, `many_to_many`, `has_one`, `has_many`, `maybe_has_many`, `has_at_least_one`, `has_and_belongs_to_many` |
| FSM | `state`, `initial`, `init`, `start`, `final`, `done` | `~>`, `edge`; use modifiers `on`, `label`, `guard` |
| Infrastructure | `user`, `client`, `gateway`, `load_balancer`, `lb`, `service`, `compute`, `database`, `db`, `managed_db`, `cache`, `queue`, `storage`, `object_store`, `internet`, `network`, `external`, `node`, `custom` | `~>`, `edge`; use modifiers `on`, `label` |
| Mind map | `root`, `topic`, `subtopic`, `note` | `branch`, `associate`, `association` |
| Planner | `task`, `todo`, `story`, `bug`, `work`, `milestone`, `release`, `phase`, `user`, `person`, `owner`, `label`, `tag` | `depends_on`, `depends`, `after`, `blocks`, `contains`, `assigned_to`, `assign`, `tagged_with`, `tagged`, `relates_to`, `relates` |
| Requirement | `requirement`, `req`, `functional`, `interface_requirement`, `performance`, `physical`, `constraint`, `design_constraint`, `component`, `service`, `module`, `system`, `test_case`, `test`, `verification`, `stakeholder`, `owner`, `team`, `actor` | `satisfies`, `verifies`, `refines`, `depends`, `traces`, `contains`, `derives`, `relates` |
| Sequence | `actor`, `participant`, `service`, `system`, `user` | `message`, `call`, `request`, `sync`, `async`, `signal`, `publish`, `reply`, `return`, `response` |
| Threat model | `external_entity`, `external`, `actor`, `user`, `client`, `third_party`, `process`, `service`, `api`, `worker`, `function`, `data_store`, `store`, `database`, `db`, `cache`, `queue`, `bucket` | `flow`, `data_flow`, `sends`, `reads`, `writes`, `encrypted`, `unencrypted` |
| UML | `class`, `struct`, `behavior`, `protocol`, `interface` | `inherits`, `extends`, `realizes`, `implements`, `associates`, `association`, `has`, `depends`, `dependency`, `uses` |
| Workflow | `begin`, `start`, `task`, `step`, `decision`, `gateway`, `fork`, `split`, `join`, `merge`, `compensation`, `rollback`, `event`, `timer`, `signal`, `finish`, `done`, `end_event`, `terminal` | `sequence`, `then`, `compensation`, `compensates`, `retry`, `failure`, `timeout`, `error` |

For machine-readable discovery, prefer `Choreo.Lab.DSL.<Diagram>.taxonomy()` in Livebook or IEx.

## Per-DSL cheat sheets

### C4

Use `Choreo.Lab.DSL.C4` for C4 context, container, and component sketches.

Canonical constructors:

- Nodes: `person`, `software_system`/`system`, `container`, `component`.
- Groups: `cluster`, `boundary`.
- Edges/modifiers: `uses`, `calls`, `sends`, `publishes`, `consumes`, `reads`, `writes`, `routes`, `depends`.
- Events: `scope`/`in_scope`.

```elixir
alias Choreo.Lab.DSL.C4, as: C4DSL

architecture =
  C4DSL.c4 do
    customer = person("Customer")
    banking = system("Banking System", scope: :in)
    api = container("API", parent: banking, technology: "Phoenix")
    db = container("Tenant DB", parent: banking, technology: "Postgres")

    customer ~> api |> uses("Submits requests", technology: "HTTPS")
    api ~> db |> reads("Tenant configuration", technology: "SQL")
    scope banking
  end
```

Nested blocks can inherit parent scope:

```elixir
C4DSL.c4 do
  system("Banking System", scope: :in) do
    api = container("API", technology: "Phoenix")
    db = container("Tenant DB", technology: "Postgres")

    api ~> db |> reads("Tenant configuration")
  end
end
```

### Dataflow

Use `Choreo.Lab.DSL.Dataflow` for pipelines with normal, error, retry, and dead-letter paths.

Canonical constructors:

- Nodes: `source`, `transform`, `buffer`, `conditional`, `merge`, `sink`.
- Groups: `cluster`, `stage`, `lane`.
- Data edges/modifiers: `emits`, `sends`, `publishes`, `consumes`, `reads`, `writes`, `routes`.
- Path edges: `normal`, `error`, `retry`, `dead_letter`.

```elixir
alias Choreo.Lab.DSL.Dataflow, as: DataflowDSL

pipeline =
  DataflowDSL.dataflow do
    ingest = source("Kafka Ingest", rate: "10k/s")
    parser = transform("JSON Parser", latency_ms: 5)
    valid = conditional("Valid?")
    warehouse = sink("Warehouse")
    dlq = sink("Dead Letter Queue")

    ingest ~> parser |> emits("raw events")
    parser ~> valid |> emits("parsed events")
    valid ~> warehouse |> writes("valid rows")
    dead_letter valid ~> dlq, "invalid rows"
  end
```

### Decision tree

Use `Choreo.Lab.DSL.DecisionTree` for routing rules, policy logic, and interview-style decision walkthroughs.

Canonical constructors:

- Nodes: `root`, `decision`, `outcome`.
- Common aliases: `question`, `result`, `leaf`.
- Edges/modifiers: `branch`, `on`, `when_`, `label`.

```elixir
alias Choreo.Lab.DSL.DecisionTree, as: DecisionDSL

policy =
  DecisionDSL.decision_tree do
    start = root("Request received")
    authenticated = decision("Authenticated?")
    allowed = outcome("Allow")
    denied = outcome("Deny")

    start ~> authenticated
    authenticated ~> allowed |> when_("yes")
    authenticated ~> denied |> when_("no")
  end
```

### Dependency

Use `Choreo.Lab.DSL.Dependency` for application/module dependencies and coupling sketches.

Canonical constructors:

- Nodes: `application`, `service`, `library`, `package`, `module`, `component`, `interface`, `test_suite`.
- Groups: `cluster`, `layer`.
- Edges/modifiers: `depends_on`, `uses`, `imports`, `calls`, `inherits`, `implements`, `dev`.

```elixir
alias Choreo.Lab.DSL.Dependency, as: DependencyDSL

deps =
  DependencyDSL.dependency do
    web = application("Web App", layer: :presentation)
    core = library("Core Domain", layer: :domain)
    adapter = package("Postgres Adapter", layer: :infrastructure)
    contract = interface("Repository Contract")

    web ~> core |> depends_on("uses domain services")
    adapter ~> contract |> implements("persists aggregates")
    core ~> contract |> depends_on("ports")
  end
```

### Domain

Use `Choreo.Lab.DSL.Domain` for DDD, context maps, event storming, and scenario paths.

Canonical constructors:

- Clusters: `context_boundary`, `bounded_context`.
- Nodes: `actor`, `command`, `aggregate`, `entity`, `event`, `read_model`, `policy`, `saga`, `external_system`, `acl`.
- Edges/modifiers: `initiates`, `handles`, `emits`, `triggers`, `projects_to`, `notifies`, `translates_via`, `shared_kernel`, `customer_supplier`, `conformist`, `open_host_service`, `published_language`, `anti_corruption`.
- Events: `scenario`.

```elixir
alias Choreo.Lab.DSL.Domain, as: DomainDSL

domain_model =
  DomainDSL.domain do
    checkout = context_boundary("Checkout")
    customer = actor("Customer")
    place_order = command("Place Order", cluster: checkout)
    order = aggregate("Order", cluster: checkout, invariants: ["Cannot place an empty order."])
    placed = event("Order Placed", cluster: checkout)
    summary = read_model("Order Summary", cluster: checkout)

    customer ~> place_order |> initiates("starts")
    place_order ~> order |> handles("validates")
    order ~> placed |> emits("records")
    placed ~> summary |> projects_to("updates")

    scenario :happy_path, "Happy path",
      path: [customer, place_order, order, placed, summary]
  end
```

Nested context blocks can assign cluster/scope automatically:

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

### ERD

Use `Choreo.Lab.DSL.ERD` for schema sketches.

Canonical constructors:

- Tables: `table`.
- Columns: `pk`, `field`, `fk`.
- Relationships: `one_to_one`, `one_to_many`, `zero_or_one_to_many`, `exactly_one_to_many`, `many_to_many`.
- Relationship aliases: `has_one`, `has_many`, `maybe_has_many`, `has_at_least_one`, `has_and_belongs_to_many`.
- Modifiers: `columns`, `from`, `to`, `label`.

```elixir
alias Choreo.Lab.DSL.ERD, as: ERDDSL

schema =
  ERDDSL.erd do
    users = table("users") do
      pk :id, :uuid
      field :email, :varchar, null: false
    end

    posts = table("posts") do
      pk :id, :uuid
      fk :user_id, :uuid
      field :title, :varchar
    end

    one_to_many users ~> posts, "writes", from: :id, to: :user_id
  end
```

The generic `~>` relationship defaults to `:one_to_many` for common parent-to-child sketches.

### FSM

Use `Choreo.Lab.DSL.FSM` for finite-state machines.

Canonical shape:

- Declare states with state constructors such as `state`, `initial`, and `final` when available in `taxonomy/0`.
- Connect states with `~>` and label transitions with `on` or explicit `edge`.

```elixir
alias Choreo.Lab.DSL.FSM, as: FSMDsl

auth_flow =
  FSMDsl.fsm do
    unauthenticated = initial("Unauthenticated")
    authenticated = state("Authenticated")
    denied = final("Denied")

    unauthenticated ~> authenticated |> on("valid token")
    edge unauthenticated ~> denied, "invalid token"
  end
```

Check the module taxonomy for the exact supported state constructors and transition metadata:

```elixir
Choreo.Lab.DSL.FSM.taxonomy()
```

### Infrastructure

Use `Choreo.Lab.DSL.Infrastructure` for deployment and runtime topology sketches.

Canonical constructors:

- Nodes: `user`, `client`, `gateway`, `load_balancer`, `service`, `compute`, `database`, `cache`, `queue`, `storage`, `internet`, `network`, `external`.
- Clusters: `vpc`, `public_subnet`, `private_subnet`, `cluster`.
- Edges/modifiers: use connection verbs exposed by `taxonomy/0`, usually via `~>` plus `on`/`label` for quick sketches.

```elixir
alias Choreo.Lab.DSL.Infrastructure, as: InfraDSL

infra =
  InfraDSL.infrastructure do
    users = user("Users")
    edge = gateway("Edge Gateway")
    api = service("API Service", replicas: 3)
    db = database("Postgres", managed: true)
    cache = cache("Redis")

    users ~> edge |> on("HTTPS")
    edge ~> api |> on("routes requests")
    api ~> db |> on("reads/writes")
    api ~> cache |> on("caches sessions")
  end
```

Infrastructure currently returns a generic `%Choreo{}` that can be cast with `Choreo.Infrastructure.from_choreo/1` when infrastructure-specific analysis is needed.

### Mind map

Use `Choreo.Lab.DSL.MindMap` for brainstorming and outline trees.

Canonical constructors:

- Nodes: `root`, `topic`, `subtopic`, `note`.
- Edges/modifiers: use `~>` and labels for parent-child or explanatory links.

```elixir
alias Choreo.Lab.DSL.MindMap, as: MindMapDSL

map =
  MindMapDSL.mind_map do
    system = root("System Design")
    scale = topic("Scale")
    storage = topic("Storage")
    cache = subtopic("Caching")

    system ~> scale
    system ~> storage
    scale ~> cache
  end
```

### Planner

Use `Choreo.Lab.DSL.Planner` for task plans, milestones, ownership, labels, and dependencies.

Canonical constructors:

- Work nodes: `task`, `story`, `bug`, `milestone`.
- Metadata nodes: `owner`, `label`.
- Edges/modifiers: `depends_on`, `blocks`, `contains`, `assigned_to`, `tagged_with`, `relates_to`.

```elixir
alias Choreo.Lab.DSL.Planner, as: PlannerDSL

plan =
  PlannerDSL.planner do
    auth = milestone("Auth v2")
    build = task("Build MFA flow")
    test = task("Add MFA tests")
    security = owner("Security Team")
    high = label("high-risk")

    auth ~> build |> contains("includes")
    test ~> build |> depends_on("after implementation")
    build ~> security |> assigned_to("owner")
    build ~> high |> tagged_with("risk")
  end
```

### Requirement

Use `Choreo.Lab.DSL.Requirement` for traceability between stakeholders, requirements, components, tests, and related artifacts.

Canonical constructors vary by requirement type; inspect `taxonomy/0` for the full list. Common patterns include:

- Requirement nodes: `requirement`, `functional`, `non_functional`.
- Artifact nodes: `component`, `test_case`, `stakeholder`.
- Edges/modifiers: `satisfies`, `verifies`, `refines`, `depends`, `traces`, `contains`, `derives`, `relates`.

```elixir
alias Choreo.Lab.DSL.Requirement, as: RequirementDSL

traceability =
  RequirementDSL.requirements "Auth v2" do
    security = stakeholder("Security Team")
    mfa = functional("Users must authenticate with MFA", id: "REQ-001", risk: :high)
    auth = component("Auth Service")
    mfa_test = test_case("MFA login test")

    security ~> mfa |> traces("owns")
    auth ~> mfa |> satisfies("implements")
    mfa_test ~> mfa |> verifies("proves")
  end
```

Remember that `id:` is the human requirement ID. Use `node_id:` to override the graph node ID.

### Sequence

Use `Choreo.Lab.DSL.Sequence` for ordered interactions.

Canonical vocabulary:

- Participants: inspect `taxonomy/0` for participant constructors such as actor/service/participant forms.
- Messages: `message`, `call`, `request`, `sync`, `async`, `signal`, `publish`, `reply`, `return`, `response`.
- Structural elements: notes and fragments are exposed in `taxonomy/0` when available.

```elixir
alias Choreo.Lab.DSL.Sequence, as: SequenceDSL

interaction =
  SequenceDSL.sequence do
    user = actor("User")
    api = participant("API")
    auth = participant("Auth Service")

    user ~> api |> request("POST /login")
    api ~> auth |> call("validate credentials")
    auth ~> api |> reply("token")
    api ~> user |> response("200 OK")
  end
```

Sequence DSLs are order-sensitive: statements are rendered in block order.

### Threat model

Use `Choreo.Lab.DSL.ThreatModel` for STRIDE-oriented DFD sketches.

Canonical constructors:

- Nodes: `external_entity`, `process`, `data_store`.
- Common aliases: `actor`, `user`, `client`, `service`, `api`, `worker`, `database`, `cache`, `queue`, `bucket`.
- Edges/modifiers: `flow`, `data_flow`, `sends`, `reads`, `writes`, `encrypted`, `unencrypted`.
- Boundaries/options: inspect `taxonomy/0` for trust-boundary constructors and flow metadata.

```elixir
alias Choreo.Lab.DSL.ThreatModel, as: ThreatDSL

model =
  ThreatDSL.threat_model do
    user = external_entity("User")
    api = process("API")
    db = data_store("User DB")

    user ~> api |> sends("credentials", protocol: "HTTPS")
    api ~> db |> writes("hashed password")
    db ~> api |> reads("user profile")
  end
```

### UML

Use `Choreo.Lab.DSL.UML` for class, struct, protocol, and interface sketches.

Canonical constructors:

- Nodes: `class`, `struct`, `behavior`, `protocol`, `interface`.
- Edges/modifiers: inspect `taxonomy/0` for association, inheritance, implementation, and dependency verbs.

```elixir
alias Choreo.Lab.DSL.UML, as: UMLDSL

classes =
  UMLDSL.uml do
    user = class("User")
    account = struct("Account")
    repo = interface("UserRepository")

    user ~> account |> on("owns")
    user ~> repo |> on("loads via")
  end
```

### Workflow

Use `Choreo.Lab.DSL.Workflow` for business processes, Sagas, approvals, CI/CD flows, and swimlane sketches.

Canonical constructors:

- Nodes: `begin`, `task`, `decision`, `fork`, `join`, `compensation`, `event`, `finish`.
- Swimlanes: `swimlane`.
- Edges/modifiers: `sequence`, `then`, `compensation`, `retry`, `failure`, `timeout`, `error`, `condition`, `when_`.

```elixir
alias Choreo.Lab.DSL.Workflow, as: WorkflowDSL

flow =
  WorkflowDSL.workflow do
    backend = swimlane("Backend")
    start = begin("Request received")
    validate = task("Validate token", swimlane: backend, timeout_ms: 100)
    authorized = decision("Authorized?")
    accepted = finish("Return 200")
    rejected = finish("Return 403")

    start ~> validate
    validate ~> authorized
    authorized ~> accepted |> condition("yes")
    failure authorized ~> rejected, "no"
  end
```

Nested swimlane blocks can apply the swimlane automatically:

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

## Compose and View

DSLs create models. `Choreo.Lab.Compose` and `Choreo.Lab.View` help combine and explore those models.

```elixir
alias Choreo.Lab.Compose
alias Choreo.Lab.View

combined =
  Choreo.new()
  |> Compose.cluster(:architecture, label: "Architecture")
  |> Compose.cluster(:auth, label: "Auth Flow")
  |> Compose.embed(architecture, into: :architecture, as: :c4)
  |> Compose.embed(auth_fsm, into: :auth, as: :auth)
  |> Compose.connect(:c4_api, :auth_idle, "uses auth flow")

focused = View.focus(combined, nodes: [:c4_api, :c4_db])
```

Prefer qualified helper calls (`Compose.embed`, `View.focus`) in notebooks to avoid import conflicts.

## Rendering in Livebook

Render models with the regular Choreo renderers:

```elixir
mermaid = Choreo.to_mermaid(architecture)
dot = Choreo.to_dot(architecture)
```

A common Livebook tab layout is:

```elixir
Kino.Layout.tabs(
  Siren: Choreo.Lab.Siren.new(mermaid),
  Graphviz: Kino.VizJS.render(dot, height: 500),
  Source: Kino.Markdown.new(mermaid)
)
```

`Choreo.Lab.Siren` defaults Mermaid to the `"default"` theme to match Livebook's light notebook canvas. You can override it:

```elixir
Choreo.Lab.Siren.new(mermaid, theme: "dark")
```

## Rendering from `.choreo.exs` files

`mix choreo.render` turns executable Choreo model files into Mermaid or DOT artifacts.

A single-artifact file can return a model as its final expression:

```elixir
# diagrams/api.choreo.exs
alias Choreo.Lab.DSL.C4, as: C4DSL

C4DSL.c4 do
  user = person("User")
  api = container("API")

  user ~> api |> uses("Calls")
end
```

Render it:

```sh
mix choreo.render diagrams/api.choreo.exs --out diagrams/api.mmd
mix choreo.render diagrams/api.choreo.exs --to dot --out diagrams/api.dot
```

A multi-artifact file can return a map or keyword list:

```elixir
%{
  architecture: architecture,
  schema: schema,
  auth_flow: auth_flow
}
```

Render all artifacts to a directory:

```sh
mix choreo.render diagrams/system.choreo.exs --out priv/diagrams/
```

For keyword lists, duplicate names use last-write-wins semantics.

### Per-artifact render options

Use tuple values when a diagram needs specific render options:

```elixir
%{
  domain_flow: domain_model,
  event_timeline: {domain_model, syntax: :event_modeling, scenario: :happy_path},
  focused_domain: {domain_model, highlighted_nodes: [:order, :placed]},
  class_view: {domain_model, syntax: :class_diagram}
}
```

CLI options are intentionally limited:

```sh
mix choreo.render FILE [--to mermaid|dot] [--out PATH] [--only NAME]
```

Diagram-specific options such as `:syntax`, `:scenario`, `:theme`, `:direction`, `:highlighted_nodes`, and `:highlighted_edges` should live in the returned artifact tuple.

## When not to use Lab DSLs

Prefer the stable pipe API when:

- building library or production application code,
- constructing models dynamically,
- sharing stable API examples,
- doing complex programmatic transformations,
- writing analysis pipelines.

The Lab DSLs are optimized for fast human sketching. The pipe APIs remain the canonical programmatic interface.
