# Behavior & Flow Modeling

Choreo provides tools for modeling, executing, analyzing, and rendering behavioral states, sequence diagrams, task orchestrations, and dataflow processing pipelines.

---

## Choreo.FSM — Finite State Machines

Classic state machines with initial states, final states, and labeled transitions.

```elixir
alias Choreo.FSM

fsm =
  FSM.new()
  |> FSM.add_initial_state(:idle)
  |> FSM.add_state(:running)
  |> FSM.add_final_state(:done)
  |> FSM.add_transition(:idle, :running, label: "start")
  |> FSM.add_transition(:running, :done, label: "finish")

# Analysis
FSM.Analysis.accepts?(fsm, ["start", "finish"])  #=> true
FSM.Analysis.shortest_accepting_path(fsm)         #=> {:ok, ["start", "finish"]}

# Render to native state diagram
FSM.to_mermaid(fsm, syntax: :state_diagram)
```

**Features:** Deterministic execution, reachability, dead-state detection, complement, product construction, equivalence checking.

```mermaid
stateDiagram-v2
  [*] --> idle
  idle --> running : start
  running --> done : finish
  done --> [*]
```

---

## Choreo.Sequence — Sequence Diagrams

Model ordered interactions between participants over time. Mermaid-native output with activation boxes, notes, and fragments.

```elixir
alias Choreo.Sequence

seq =
  Sequence.new()
  |> Sequence.add_actor(:user, label: "User")
  |> Sequence.add_participant(:api, label: "API")
  |> Sequence.add_participant(:db, label: "Database")
  |> Sequence.message(:user, :api, label: "GET /accounts")
  |> Sequence.activate(:api)
  |> Sequence.message(:api, :db, label: "SELECT * FROM accounts")
  |> Sequence.return(:db, :api, label: "rows")
  |> Sequence.deactivate(:api)
  |> Sequence.return(:api, :user, label: "200 OK")

Sequence.to_mermaid(seq)
Sequence.to_dot(seq)        # Best-effort timeline fallback
```

**Features:** actors/participants, sync/async/return/self messages, activation boxes, notes, loops/alts/opts, missing-label detection, unbalanced activation detection.

```mermaid
sequenceDiagram
    actor User
    participant API
    participant Database
    User->>API: GET /accounts
    activate API
    API->>Database: SELECT * FROM accounts
    Database-->>API: rows
    API-->>User: 200 OK
    deactivate API
```

---

## Choreo.Workflow — Task Orchestration

Model automated task orchestration with Saga-pattern compensations, timeouts, retries, and conditional branching.

```elixir
alias Choreo.Workflow
alias Choreo.Workflow.Analysis

workflow =
  Workflow.new()
  |> Workflow.add_start(:order_received)
  |> Workflow.add_task(:charge_card, timeout_ms: 5000, retry: 3)
  |> Workflow.add_task(:reserve_inventory, timeout_ms: 3000)
  |> Workflow.add_decision(:sufficient_stock)
  |> Workflow.add_task(:pack_items, timeout_ms: 10_000)
  |> Workflow.add_task(:ship_order, timeout_ms: 5000)
  |> Workflow.add_compensation(:refund_payment, for: :charge_card)
  |> Workflow.add_end(:done)
  |> Workflow.connect(:order_received, :charge_card)
  |> Workflow.connect(:charge_card, :reserve_inventory)
  |> Workflow.connect(:reserve_inventory, :sufficient_stock)
  |> Workflow.connect(:sufficient_stock, :pack_items, condition: "yes")
  |> Workflow.connect(:sufficient_stock, :refund_payment, condition: "no", edge_type: :compensation)
  |> Workflow.connect(:pack_items, :ship_order)
  |> Workflow.connect(:ship_order, :done)

# Analysis
Analysis.critical_path(workflow)
#=> {:ok, [:order_received, :charge_card, ...], 23000}

Analysis.parallelizable_tasks(workflow)
Analysis.missing_compensations(workflow)
Analysis.validate(workflow)
```

**Features:** critical-path analysis with latency weights, parallelizable-task grouping, failure-scenario detection, missing-compensation detection, bottleneck detection, execution simulation.

```mermaid
graph TD
  classDef default color:white
  done(("done"))
  order_received(("order_received"))
  charge_card[["charge_card (5000ms) retry: 3"]]
  reserve_inventory[["reserve_inventory (3000ms)"]]
  sufficient_stock{"sufficient_stock"}
  pack_items[["pack_items (10000ms)"]]
  ship_order[["ship_order (5000ms)"]]
  refund_payment["refund_payment"]
  style done fill:#ef4444,stroke:#d12626,stroke-width:3px
  style order_received fill:#10b981,stroke:#009b63,stroke-width:2px
  style charge_card fill:#3b82f6,stroke:#1d64d8
  style reserve_inventory fill:#3b82f6,stroke:#1d64d8
  style sufficient_stock fill:#8b5cf6,stroke:#6d3ed8
  style pack_items fill:#3b82f6,stroke:#1d64d8
  style ship_order fill:#3b82f6,stroke:#1d64d8
  style refund_payment fill:#f87171,stroke:#ef4444,stroke-width:2px,stroke-dasharray:3 3
  order_received --> charge_card
  charge_card --> reserve_inventory
  reserve_inventory --> sufficient_stock
  sufficient_stock -->|yes| pack_items
  sufficient_stock -->|no| refund_payment
  pack_items --> ship_order
  ship_order --> done
  linkStyle 0 stroke-width:2px,stroke:#64748b
  linkStyle 1 stroke-width:2px,stroke:#64748b
  linkStyle 2 stroke-width:2px,stroke:#64748b
  linkStyle 3 stroke-width:2px,stroke:#64748b
  linkStyle 4 stroke-width:2px,stroke:#64748b,stroke-dasharray:5 5
  linkStyle 5 stroke-width:2px,stroke:#64748b
  linkStyle 6 stroke-width:2px,stroke:#64748b
```

---

## Choreo.Dataflow — Pipeline Diagrams

Model stream-processing and ETL pipelines. Nodes are sources, transforms, buffers, conditionals, merges, and sinks.

```elixir
alias Choreo.Dataflow

pipeline =
  Dataflow.new()
  |> Dataflow.add_source(:sensor, label: "IoT Sensor", rate: 1000)
  |> Dataflow.add_transform(:parse, label: "JSON Parser", latency_ms: 50)
  |> Dataflow.add_buffer(:kafka, label: "Events", capacity: 10_000)
  |> Dataflow.add_sink(:db, label: "TimescaleDB")
  |> Dataflow.connect(:sensor, :parse, data_type: "raw bytes")
  |> Dataflow.connect(:parse, :kafka, data_type: "event")
  |> Dataflow.connect(:kafka, :db, data_type: "metrics")

# Analysis
Dataflow.Analysis.cyclic?(pipeline)           #=> false
{:ok, order} = Dataflow.Analysis.topological_sort(pipeline)
Dataflow.Analysis.orphan_nodes(pipeline)       #=> []
Dataflow.Analysis.bottlenecks(pipeline)        #=> [:kafka]
Dataflow.Analysis.simulate(pipeline)           #=> throughput map
{:ok, path, latency} = Dataflow.Analysis.longest_path(pipeline)
```

**Features:** error/retry/dead-letter path types, sub-pipeline clusters, throughput simulation, backpressure detection, critical-path analysis.

```mermaid
graph TD
  classDef default color:white
  parse[["JSON Parser"]]
  db["TimescaleDB"]
  sensor(["IoT Sensor<br/>1000 evt/s"])
  kafka[("Events<br/>(cap: 10000)")]
  style parse fill:#3b82f6
  style db fill:#f43f5e
  style sensor fill:#10b981
  style kafka fill:#f59e0b
  parse -->|event| kafka
  sensor -->|raw bytes| parse
  kafka -->|metrics| db
  linkStyle 0 stroke-width:2px,stroke:#64748b
  linkStyle 1 stroke-width:2px,stroke:#64748b
  linkStyle 2 stroke-width:2px,stroke:#64748b
```
