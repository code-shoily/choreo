# Lab DSLs and Sketch Syntax

Choreo's stable APIs are pipe-first and explicit. The `Choreo.Lab.DSL.*` modules are a lighter sketch layer for Livebook exploration, tutorials, interviews, and quick architecture thinking.

Use the Lab DSLs when you want to move quickly from an idea to a model. Use the stable pipe APIs when you want maximum explicitness, dynamic construction, or library/application code.

## Philosophy

The Lab DSLs follow a small set of rules:

- DSLs compile down to existing stable builders.
- DSLs return ordinary Choreo structs.
- The stable pipe APIs remain canonical.
- Analysis stays explicit; there is no analysis DSL.
- Rendering and styling remain renderer concerns.
- The DSL grammar stays small, strict, and domain-oriented.
- Unknown variables raise instead of silently creating surprising nodes.

A useful mental model is:

```text
Lab DSLs create models.
Lab Compose combines models.
Lab View explores models.
Renderers present models.
Analysis remains explicit.
```

## Shared grammar

Most Lab DSLs share the same visual shape:

```elixir
node = constructor("Label")
other = constructor("Other")

node ~> other
node ~> other |> verb("meaning")
edge node ~> other, "label"
typed_edge node ~> other, "label"
```

Examples across domains:

```elixir
api ~> db |> reads("tenant config")
stream ~> warehouse |> writes("analytics rows")
idle ~> authenticated |> on("valid token")
order ~> order_placed |> emits("records")
auth_service ~> mfa |> satisfies("implements")
```

The arrow shows graph shape. The pipe modifier carries domain semantics.

## Identity rule

DSL constructors use this identity rule:

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

## Current DSLs

The current Lab DSL modules are:

- `Choreo.Lab.DSL.Infrastructure` — deployment and runtime infrastructure sketches.
- `Choreo.Lab.DSL.FSM` — finite-state machine sketches.
- `Choreo.Lab.DSL.MindMap` — mind-map brainstorming and outline sketches.
- `Choreo.Lab.DSL.ERD` — entity relationship and schema sketches.
- `Choreo.Lab.DSL.UML` — class/struct/protocol sketches.
- `Choreo.Lab.DSL.Dataflow` — sources, transforms, sinks, queues, and paths.
- `Choreo.Lab.DSL.Sequence` — ordered interactions, messages, notes, and fragments.
- `Choreo.Lab.DSL.C4` — C4 context/container/component sketches.
- `Choreo.Lab.DSL.DecisionTree` — decision policy and routing sketches.
- `Choreo.Lab.DSL.Workflow` — process, orchestration, Saga, and swimlane sketches.
- `Choreo.Lab.DSL.Dependency` — software dependency and coupling sketches.
- `Choreo.Lab.DSL.Requirement` — requirement traceability sketches.
- `Choreo.Lab.DSL.Domain` — DDD, context mapping, event storming, and scenarios.

## Example: C4

```elixir
alias Choreo.Lab.DSL.C4, as: C4DSL

architecture =
  C4DSL.c4 do
    customer = person("Customer")
    gateway = system("API Gateway", scope: :in)
    api = container("Gateway API", parent: gateway, technology: "Phoenix")
    db = database("Tenant DB", parent: gateway, technology: "Postgres")

    customer ~> api |> uses("Submits API requests", technology: "HTTPS")
    api ~> db |> reads("Tenant configuration", technology: "SQL")
    scope gateway
  end
```

## Example: Domain

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

## Example: Requirement traceability

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
  Source: Kino.Markdown.new("```mermaid\n#{mermaid}\n```")
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
