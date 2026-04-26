# Changelog

## [Unreleased]

### Changed

- **Breaking:** Restored pure DFA boundaries across execution engines.
- Dropped ambiguous NFA mappings (`Analysis.to_dfa/1`).
- Refactored `%Choreo.FSM{meta: %{initial_state: state}}` singular state vectors.
- All edge builders now raise `ArgumentError` on duplicate `(from, to)` pairs instead of silently overwriting:
  - `Choreo.FSM.add_transition/4`
  - `Choreo.Dataflow.connect/4`
  - `Choreo.Workflow.connect/4`
  - `Choreo.Dependency.depends_on/4`
  - `Choreo.ThreatModel.data_flow/4`
- Documented single-edge-per-pair limitation in all edge-builder docstrings. Multigraph support (parallel edges) is planned for a future release.

## 0.6.0 — 2026-04-25

### Added

- `Choreo.FSM.remove_initial_state/2` — explicitly demotes a state from initial status without deleting the node.
- `Choreo.FSM.remove_final_state/2` — explicitly demotes a state from final status without deleting the node.

### Changed

- **Breaking:** `Choreo.FSM` state typing moved from node `state_type` field to `meta` MapSets (`initial_states` and `final_states`). `add_state/3` with `type: :initial` or `type: :final` now populates these sets directly.
- `Choreo.FSM.add_state/3` with `type: :normal` now explicitly clears a state from both `initial_states` and `final_states` in meta. Omitting the `:type` option (e.g. updating a label) preserves existing status.
- `Choreo.FSM.Analysis.deterministic?/1` now enforces a **single initial state** in addition to unique outgoing transition labels, aligning with classical DFA definition.

### Fixed

- `add_state/3 with type: :initial` now correctly registers the state in `meta.initial_states` so that `reachable_states/1`, `accepts?/2`, and rendering treat it as an entry point.
- Fixed broken doctests in `Choreo.FSM.add_initial_state/2` and `Choreo.FSM.add_final_state/2` that still referenced the removed `state_type` node field.

## 0.5.0 — 2026-04-24

### Added

- `Choreo.Workflow` — task orchestration builder with Saga-pattern compensation support
  - Nodes: `add_start/3`, `add_end/3`, `add_task/3`, `add_decision/3`, `add_fork/3`, `add_join/3`, `add_compensation/3`, `add_event/3`
  - Edge types: `:sequence`, `:compensation`, `:retry`, `:failure`, `:timeout`
  - Swimlane grouping for visual organization
  - Analysis: `critical_path/1`, `parallelizable_tasks/1`, `failure_scenarios/1`, `missing_compensations/1`, `bottlenecks/2`, `simulate/1`, `validate/1`
- Internal helpers module — shared `bfs_reachable/2`, `build_cluster_subgraphs/2`, `best_predecessor/3` extracted to eliminate Credo duplicate-code warnings

### Changed

- **Breaking:** Package and all modules renamed from `YogSystem` to `Choreo`
- `Choreo.DecisionTree.set_root/3` and `branch/4` now return `t()` directly (pipeable), raising `ArgumentError` on invalid use. Removed redundant `branch!/4`.

### Fixed

- All `mix credo --strict` warnings resolved (double filters, deep nesting, unused aliases, list append inefficiencies, `Enum.map_join/3` usage, `with`→`case` conversions)
- Incorrect `@spec` return types for edge-returning functions (`String.t()` → `number()`)

## 0.1.0 — 2026-04-24

### Added

- `Choreo` — infrastructure architecture diagrams with typed nodes (database, cache, service, queue, etc.), clusters, and MST/topological-sort analysis
- `Choreo.FSM` — finite-state machine builder with initial/final states, transitions, determinism checks, NFA simulation, equivalence checking, and pruning
- `Choreo.Dataflow` — pipeline / ETL diagram builder with sources, transforms, buffers, conditionals, merges, and sinks
  - Analysis: cycle detection, topological sort, orphan/dead-end detection, bottlenecks, critical-path (longest path), throughput simulation, backpressure detection
  - Edge types: normal, error, retry, dead-letter
  - Cluster support
- `Choreo.Dependency` — software dependency graphs with applications, libraries, modules, interfaces, and tests
  - Analysis: circular dependency extraction (actual paths), impact analysis (`affected_by/2`, `depends_on/2`), layer violation detection, centrality ranking, longest dependency chain
  - Cycle edge highlighting in DOT output
- `Choreo.DecisionTree` — classification tree builder with enforced tree invariants
  - Analysis: `decide/2` evaluation, path enumeration, depth/breadth metrics, feature importance, redundant-branch pruning
- `Choreo.ThreatModel` — STRIDE threat modeling with automated threat generation
  - Analysis: auto-generated STRIDE threats per element type, trust-boundary crossing detection, exposed data stores, high-risk processes, unencrypted flow detection
  - Severity scoring based on sensitivity, privilege, encryption, and trust level
- Shared DOT rendering pipeline with `:default`, `:dark`, and custom `Choreo.Theme` support
- Graphviz integration in ExDoc for inline diagram rendering
- Credo, Dialyzer, and ExCoveralls tooling
