# Choreo Analysis Algorithms Reference

Choreo turns every diagram into a graph, then runs classic graph algorithms on it to answer practical questions: "Will this deployment order work?", "What breaks if this service fails?", "Where are the cycles?", and so on.

This guide catalogs the analysis functions in each diagram module, what question they answer, and the underlying algorithm they use. The implementations live in `lib/choreo/analysis.ex`, `lib/choreo/internal.ex`, the `lib/choreo/*/analysis.ex` modules, and `lib/choreo/analysis/tracing.ex`.

Most functions build on the [`yog_ex`](https://hex.pm/packages/yog_ex) graph library, which provides BFS/DFS, topological sort, strongly connected components, shortest paths, MST, centrality, and connectivity primitives.

---

## Supported diagram types

| Diagram type | Main module | Analysis module | Typical use |
|---|---|---|---|
| System architecture | `Choreo` | `Choreo.Analysis` | Services, databases, caches, queues |
| C4 model | `Choreo.C4` | `Choreo.C4.Analysis` | Software architecture views |
| Cloud infrastructure | `Choreo.Infrastructure` | `Choreo.Infrastructure.Analysis` | VPC/subnet/security audits |
| Finite-state machines | `Choreo.FSM` | `Choreo.FSM.Analysis` | State machines and automata |
| Dataflow / pipelines | `Choreo.Dataflow` | `Choreo.Dataflow.Analysis` | Streaming/data pipelines |
| Dependency graphs | `Choreo.Dependency` | `Choreo.Dependency.Analysis` | Module/library dependencies |
| Decision trees | `Choreo.DecisionTree` | `Choreo.DecisionTree.Analysis` | Classification trees |
| Threat models | `Choreo.ThreatModel` | `Choreo.ThreatModel.Analysis` | STRIDE threat modeling |
| Workflows | `Choreo.Workflow` | `Choreo.Workflow.Analysis` | BPMN/saga workflows |
| Planner / tasks | `Choreo.Planner` | `Choreo.Planner.Analysis` | Project/task planning |
| Mind maps | `Choreo.MindMap` | `Choreo.MindMap.Analysis` | Hierarchical idea maps |
| Entity-relationship diagrams | `Choreo.ERD` | `Choreo.ERD.Analysis` | Database schemas |
| UML class diagrams | `Choreo.UML` | `Choreo.UML.Analysis` | Software design |
| Domain / event storming | `Choreo.Domain` | `Choreo.Domain.Analysis` | Domain-driven design |
| Sequence diagrams | `Choreo.Sequence` | `Choreo.Sequence.Analysis` | Message sequence validation |
| Requirements | `Choreo.Requirement` | `Choreo.Requirement.Analysis` | Requirements traceability |
| Cross-diagram tracing | — | `Choreo.Analysis.Tracing` | Trace edges across diagrams |

---

## Core / cross-cutting analysis

### `Choreo.Analysis` — system architecture

These functions operate on the general `Choreo` architecture graph. Many of them are re-used or mirrored by diagram-specific modules.

| Function | Purpose | Algorithm used |
|---|---|---|
| `mst/2` | Cheapest way to connect all services | **MST** — Kruskal (default), Prim, or Borůvka on an undirected simple graph |
| `topological_sort/1` | Deployment or execution order | **Topological sort** via `Yog.Traversal.topological_sort/1` (Kahn / DFS-based) |
| `cyclic?/1` | Detect feedback loops | **Cycle detection** via `Yog.cyclic?/1` |
| `dag?/1` | Check if the graph is acyclic | **Acyclicity check** via `Yog.acyclic?/1` |
| `strongly_connected_components/1` | Find mutually dependent services | **Strongly Connected Components (SCC)** via `Yog.Connectivity` |
| `single_points_of_failure/1` | Find articulation points and bridge edges | **Tarjan's articulation-point/bridge algorithm** on an undirected view |
| `cut_vertices/1` | Nodes whose removal disconnects the graph | **Tarjan's articulation points** |
| `impact_analysis/2` | What breaks if a node fails | **BFS on the transposed graph** |
| `shortest_path/4` | Cheapest/fastest route between services | **Dijkstra / shortest path** with semiring support (cost, latency, custom metrics) |
| `path/4` | Domain-specific pathfinding | **Dijkstra / widest path** with measures `:shortest`, `:latency`, `:throughput`, `:risk`, `:weighted` |
| `centrality/2` | Most critical or coupled nodes | **Degree / betweenness / closeness / PageRank** centrality via `Yog.Centrality` |
| `core_numbers/1` | K-core decomposition | **K-core decomposition** via `Yog.Connectivity.core_numbers/1` |
| `reduce_transitive/1` | Remove redundant edges while preserving reachability | **Transitive reduction** |
| `isolated_nodes/1` | Find orphan services | In-degree + out-degree check |
| `heatmap/2` | Color nodes by centrality or score | Centrality → min-max normalization → color scale |
| `validate/1` | Structural health check | Composite: isolated nodes, SPOF, cycles, bridges |

### `Choreo.Analysis.Tracing` — cross-diagram tracing

| Function | Purpose | Algorithm used |
|---|---|---|
| `impact_analysis/2` | Nodes transitively impacted via trace edges | **BFS on the transposed trace-only graph** |
| `trace_path/3` | Shortest trace path between two nodes | **Dijkstra** on the trace-only graph |
| `analyze/3` | Nested cross-domain analysis along a trace path | Path reconstruction + domain metadata classification |

### `Choreo.Internal` — shared graph primitives

| Function | Purpose | Algorithm used |
|---|---|---|
| `bfs_reachable/2` | Reachable nodes from seed nodes | **Breadth-First Search (BFS)** |
| `transitive_reduction/1` | Redundant edges implied by longer paths | **BFS reachability** from alternate successors |
| `compute_dp/3` | Longest-path DP table | **Dynamic programming over a topological order** |
| `find_best_end_path/2` | Best predecessor chain | Linear scan of the DP table |
| `reconstruct_path/2` | Reconstruct a path from DP predecessors | Backtracking |
| `dfs_cycles/1` | All elementary cycles in a multigraph | **Depth-First Search (DFS)** with recursion-stack tracking |
| `unsatisfied_contract/3` | Missing functions for a contract | Set difference on function name/arity |

---

## Diagram-specific analysis

### `Choreo.C4.Analysis` — C4 architecture model validation

| Function | Purpose | Algorithm used |
|---|---|---|
| `isolated_nodes/1` | Elements with no relationships | In-degree + out-degree on a simple graph |
| `missing_parents/1` | Containers/components without parents | Metadata filter |
| `missing_descriptions/1` | Nodes lacking descriptions | Metadata filter |
| `missing_technology/1` | Containers/components without technology labels | Metadata filter |
| `missing_relationship_labels/1` | Relationships lacking labels | Edge metadata filter |
| `parents_without_relationships/1` | Parent nodes with children but no edges | Degree + parent metadata check |
| `validate/1` | Full C4 model validation | Composite rule check |

### `Choreo.Infrastructure.Analysis` — cloud topology audits

| Function | Purpose | Algorithm used |
|---|---|---|
| `validate/1` | Security audit (internet-to-private, DB placement, LB placement, etc.) | Rule-based set membership checks on node/edge metadata |
| `warnings/1` | Audit warnings | Rule-based set membership checks |

### `Choreo.FSM.Analysis` — finite-state machines

| Function | Purpose | Algorithm used |
|---|---|---|
| `reachable_states/1` | States reachable from the initial state | **BFS** |
| `dead_states/1` | States with no path to a final state | **Reverse BFS** from final states |
| `livelock_states/1` | Reachable non-accepting loop states | Intersection of reachable/dead + **BFS self-reachability** |
| `accepts?/2` | Simulate input string acceptance | Deterministic walk |
| `shortest_accepting_path/1` | Minimum input to reach acceptance | **BFS** |
| `accepted_strings/2` | All accepted strings up to length N | **BFS level-order expansion** |
| `alphabet/1` | Distinct input symbols | Set construction |
| `complete?/1` | Whether every state handles every symbol | Set subset check |
| `generate_test_cases/2` | Input sequences for state/transition coverage | **BFS shortest paths** to all states |
| `equivalent?/2` | Check if two FSMs accept the same language | **Product automaton BFS** |
| `minimize/1` | Minimize a DFA | **Moore's partition refinement** |
| `violates_invariant?/2` | Forbidden state sequence exists | Edge existence check |
| `validate/1` | Structural FSM validation | Composite checks |

### `Choreo.Dataflow.Analysis` — streaming/data pipelines

| Function | Purpose | Algorithm used |
|---|---|---|
| `sources/1` / `sinks/1` | Identify source/sink nodes | Node type filter |
| `cyclic?/1` | Feedback-loop detection | Cycle detection on the normal-edge subgraph |
| `topological_sort/1` | Stage execution order | **Topological sort** |
| `orphan_nodes/1` | Nodes unreachable from any source | **BFS** from sources + set difference |
| `dead_ends/1` | Nodes that cannot reach any sink | **BFS on the transposed graph** from sinks |
| `fan_hubs/1` | High in-degree + out-degree stages | Degree threshold |
| `longest_path/1` | Critical path (longest source→sink chain) | **DP over topological order** |
| `capacity_bottlenecks/1` | Stages where in_rate > capacity | **Throughput simulation** via topological propagation |
| `simulate/1` | Steady-state throughput simulation | **Topological-order traversal** + rate summation |
| `backpressure_points/1` | Nodes with inbound flow above threshold | Simulation result filter |
| `upstream_lineage/1` / `downstream_impact/1` | Ancestors/descendants | **BFS** (transposed for upstream) |
| `upstream_sources/1` / `downstream_sinks/1` | Source/sink subsets of lineage | BFS + set intersection |
| `heatmap/2` | Throughput heatmap | Simulation → color scale |
| `validate/1` | Pipeline structural validation | Composite checks |

### `Choreo.Dependency.Analysis` — dependency graphs

| Function | Purpose | Algorithm used |
|---|---|---|
| `cyclic_dependencies/1` | All circular dependency chains | **SCC** + DFS cycle extraction |
| `affected_by/2` | Components that break if the target changes | **BFS on the transposed graph** |
| `depends_on/2` | Components the target depends on | **BFS** |
| `layer_violations/2` | Edges violating layered architecture | Edge + layer-index comparison |
| `centrality/2` | Most coupled components | Degree centrality (in + out) |
| `leaves/1` / `roots/1` | Nodes with no dependents / no dependencies | In-degree / out-degree filter |
| `transitive_reduction/1` | Redundant explicit dependencies | **Transitive reduction** |
| `instability/1` | Instability metric per component | `Ce / (Ca + Ce)` |
| `isolated_subsystems/1` | Disconnected component groups | **Weakly connected components** |
| `longest_dependency_chain/1` | Deepest dependency chain | **DP over topological order** |
| `validate/1` | Dependency graph validation | Composite checks |

### `Choreo.DecisionTree.Analysis` — decision trees

| Function | Purpose | Algorithm used |
|---|---|---|
| `decide/2` | Evaluate tree against feature values | Tree walk |
| `paths/1` | All root-to-leaf paths | **DFS enumeration** |
| `paths_with_conditions/1` | Paths with branch conditions | **DFS enumeration** |
| `depth/1` / `breadth/1` | Tree depth / leaf count | Recursive traversal / count |
| `feature_importance/1` | Feature split frequency | Group-by + count |
| `reachable_outcomes/1` | Reachable outcome classes | **BFS** |
| `orphan_nodes/1` | Unreachable declared nodes | **BFS** + set difference |
| `rules/1` | Extract IF-THEN rules | Path-to-conditions mapping |
| `generate_test_cases/1` | Feature maps covering every leaf | Path conditions |
| `missing_branches/2` | Expected feature values not covered | Set difference |
| `inconsistent_paths/1` | Logically impossible paths | Path condition grouping |
| `prune_redundant/1` | Remove redundant decision nodes | **Post-order tree traversal** |
| `validate/1` | Tree structural validation | Composite checks |

### `Choreo.ThreatModel.Analysis` — STRIDE threat modeling

| Function | Purpose | Algorithm used |
|---|---|---|
| `stride_threats/2` | Generate STRIDE threats | Rule-based generation by element type |
| `threat_summary/1` | Threat distribution by category/severity | Aggregation |
| `risk_score/2` | Total weighted risk score | Weighted sum by severity |
| `cross_boundary_flows/1` | Data flows crossing trust boundaries | Boundary comparison |
| `exposed_data_stores/1` | Data stores reachable from external entities | **BFS** from external entities |
| `attack_paths/1` | Paths from externals to data stores | **DFS path enumeration** |
| `high_risk_processes/1` | Low-trust processes accessing sensitive stores | **BFS** + risk/trust checks |
| `unencrypted_boundary_flows/1` | Unencrypted cross-boundary flows | Edge metadata + boundary check |
| `heatmap/2` | Threat density heatmap | Threat count → color scale |
| `validate/1` | Threat model validation | Composite checks |

### `Choreo.Workflow.Analysis` — workflows and orchestration

| Function | Purpose | Algorithm used |
|---|---|---|
| `reachable_tasks/1` | Tasks reachable from start nodes | **BFS** |
| `orphan_tasks/1` | Tasks not reachable from starts | **BFS** + set difference |
| `dead_ends/1` | Tasks that cannot reach an end node | **BFS on the transposed graph** from ends |
| `critical_path/1` | Longest latency path start→end | **DP over topological order** |
| `parallelizable_tasks/1` | Tasks that can run in parallel | **Topological levels** |
| `compensable_tasks/1` | Tasks with compensation edges | Edge metadata check |
| `uncompensated_paths/1` | Failing tasks without valid compensation | **BFS** on the compensation subgraph |
| `missing_compensations/1` | Retry-configured tasks lacking compensations | Metadata check |
| `bottlenecks/2` | High-latency / high-retry tasks | Threshold filter |
| `simulate/1` | Estimated latency per task | **Topological-order latency propagation** |
| `heatmap/2` | Cumulative latency heatmap | Simulation → color scale |
| `validate/1` | Workflow structural validation | Composite checks |

### `Choreo.Planner.Analysis` — project/task planning

| Function | Purpose | Algorithm used |
|---|---|---|
| `ready/1` | Tasks whose dependencies are done | Status + dependency resolution |
| `blocked/1` | Tasks with unresolved dependencies | Status + dependency resolution |
| `orphans/1` | Tasks not in any milestone | Parent metadata check |
| `critical_path/2` | Longest dependency chain by estimate | **DP over topological order** |
| `bottlenecks/1` | Tasks ranked by transitive downstream impact | **BFS reachability count** |
| `validate/1` | Structural integrity checks | Composite: cycles, unassigned tasks, orphans, empty milestones |

### `Choreo.MindMap.Analysis` — mind maps

| Function | Purpose | Algorithm used |
|---|---|---|
| `depth/1` | Maximum depth from root | **DFS** with cycle guard |
| `breadth/1` / `leaves/1` | Leaf count / leaf nodes | Out-degree filter |
| `orphan_nodes/1` | Nodes not reachable from root | **BFS** on branch edges |
| `max_width/1` | Widest level | **BFS level counting** |
| `paths/1` | All root-to-leaf paths | **DFS enumeration** |
| `type_frequencies/1` | Node type composition | Group-by + count |
| `cyclic?/1` | Cycle in hierarchy | Cycle detection |
| `suggest_merges/2` | Candidate node pairs to merge | **Jaccard similarity** of neighborhoods |
| `validate/1` | Structural validation | Composite checks |

### `Choreo.ERD.Analysis` — database schemas

| Function | Purpose | Algorithm used |
|---|---|---|
| `shortest_join_path/3` | Optimal join sequence | Path finding on an **undirected** simple graph |
| `cycles/1` | Circular foreign-key references | **DFS cycle detection** |
| `orphans/1` | Tables with no relationships | Degree check |
| `table_degrees/1` | In/out/total coupling per table | Degree metrics |
| `affected_by/2` | Tables that reference target transitively | **BFS on the transposed graph** |
| `depends_on/2` | Tables the target depends on | **BFS** |
| `transitive_reduction/1` | Redundant relationships | **Transitive reduction** |
| `longest_dependency_chain/1` | Deepest FK cascade | **DP over topological order** |
| `normalization_score/2` | Schema quality score | Heuristic penalty scoring |
| `validate/1` | ERD structural validation | Composite checks |

### `Choreo.UML.Analysis` — UML class diagrams

| Function | Purpose | Algorithm used |
|---|---|---|
| `cycles/1` | Circular dependency loops | **DFS cycle detection** |
| `broken_contracts/1` | Incomplete interface/behavior realizations | Contract function comparison |
| `coupling_metrics/1` | Afferent/efferent coupling and instability | In/out degree + `Ce/(Ca+Ce)` |
| `law_of_demeter_violations/1` | Structural Law of Demeter violations | Triplet enumeration (`A→B`, `B→C`, `A→C`) |
| `affected_by/2` | Classes that depend on target | **BFS on the transposed graph** |
| `depends_on/2` | Classes target depends on | **BFS** |
| `transitive_reduction/1` | Redundant relationships | **Transitive reduction** |
| `validate/1` | UML structural validation | Composite checks |

### `Choreo.Domain.Analysis` — event storming / domain models

| Function | Purpose | Algorithm used |
|---|---|---|
| `validate/1` / `warnings/1` | Semantic validation of events/commands/policies | Rule-based adjacency-map checks |
| `ubiquitous_language/1` | Markdown glossary from nodes | Sort + format |

### `Choreo.Sequence.Analysis` — sequence diagrams

| Function | Purpose | Algorithm used |
|---|---|---|
| `validate/1` | Full sequence diagram validation | Composite checks |
| `isolated_participants/1` | Participants with no messages | Set difference |
| `missing_labels/1` | Messages without labels | Metadata filter |
| `unknown_participants/1` | References to undeclared participants | Set membership check |
| `unbalanced_activations/1` | Unmatched activate/deactivate pairs | Stack balance |
| `unclosed_fragments/1` | Fragments opened but not closed | Stack balance on reversed events |

### `Choreo.Requirement.Analysis` — requirements traceability

| Function | Purpose | Algorithm used |
|---|---|---|
| `orphan_requirements/1` | Requirements with no relationships | Set difference |
| `unsatisfied/1` / `unverified/1` | Requirements missing satisfies/verifies edges | Edge metadata check |
| `coverage/1` | Coverage ratios | Set operations |
| `traceability_matrix/1` | Requirements → components/tests/stakeholders | Edge aggregation |
| `requirements_for/2` / `components_for/2` | Related nodes by edge type | Edge traversal |
| `high_risk_gaps/1` | High-risk requirements not satisfied/verified | Set intersection |
| `risk_propagation/1` | Inherited risk from ancestors | **Recursive ancestor traversal** |
| `unmitigated_risks/1` | High-risk items without lower-risk children | Risk-level comparison |
| `impact_of/2` | Upstream + downstream affected nodes | **BFS in both directions** |
| `circular_dependencies/1` | Cycles among requirement relationships | **Tarjan's SCC** |
| `validate/1` | Requirements validation | Composite checks |

---

## Algorithm index

A quick lookup of which algorithms appear where.

| Algorithm | Used by |
|---|---|
| **BFS** | `Choreo.Analysis.impact_analysis/2`, `Choreo.Dataflow` reachability/lineage, `Choreo.Dependency.affected_by/2`, `Choreo.ERD.affected_by/2`, `Choreo.UML.affected_by/2`, `Choreo.FSM`, `Choreo.Workflow`, `Choreo.MindMap`, `Choreo.ThreatModel.exposed_data_stores/1`, `Choreo.Requirement.impact_of/2`, `Choreo.Internal.bfs_reachable/2` |
| **DFS** | `Choreo.ERD.cycles/1`, `Choreo.UML.cycles/1`, `Choreo.MindMap.paths/1`, `Choreo.DecisionTree.paths/1`, `Choreo.ThreatModel.attack_paths/1`, `Choreo.Internal.dfs_cycles/1` |
| **Topological sort** | `Choreo.Analysis.topological_sort/1`, `Choreo.Dataflow`, `Choreo.Dependency.longest_dependency_chain/1`, `Choreo.ERD.longest_dependency_chain/1`, `Choreo.Workflow.critical_path/1`, `Choreo.Planner.critical_path/2`, `Choreo.Dataflow.simulate/1` |
| **SCC (Tarjan)** | `Choreo.Analysis.strongly_connected_components/1`, `Choreo.Dependency.cyclic_dependencies/1`, `Choreo.Requirement.circular_dependencies/1` |
| **Articulation points / bridges** | `Choreo.Analysis.single_points_of_failure/1`, `Choreo.Analysis.cut_vertices/1` via `Yog.Connectivity.analyze/1` |
| **Shortest path (Dijkstra)** | `Choreo.Analysis.shortest_path/4`, `Choreo.Analysis.path/4`, `Choreo.Analysis.Tracing.trace_path/3` |
| **Widest path** | `Choreo.Analysis.path/4` (`:throughput`, `:weighted`) |
| **MST (Kruskal/Prim/Borůvka)** | `Choreo.Analysis.mst/2` |
| **Longest path in DAG** | `Choreo.Dataflow.longest_path/1`, `Choreo.Dependency.longest_dependency_chain/1`, `Choreo.ERD.longest_dependency_chain/1`, `Choreo.Workflow.critical_path/1`, `Choreo.Planner.critical_path/2` via `Choreo.Internal.compute_dp/3` |
| **Transitive reduction** | `Choreo.Analysis.reduce_transitive/1`, `Choreo.Dependency.transitive_reduction/1`, `Choreo.ERD.transitive_reduction/1`, `Choreo.UML.transitive_reduction/1`, `Choreo.Internal.transitive_reduction/1` |
| **Centrality** | `Choreo.Analysis.centrality/2` (degree, betweenness, closeness, PageRank) |
| **K-core decomposition** | `Choreo.Analysis.core_numbers/1` |
| **Weakly connected components** | `Choreo.Dependency.isolated_subsystems/1` |
| **DFA minimization (Moore's partition refinement)** | `Choreo.FSM.Analysis.minimize/1` |
| **Product automaton BFS** | `Choreo.FSM.Analysis.equivalent?/2` |
| **Jaccard similarity** | `Choreo.MindMap.Analysis.suggest_merges/2` |
| **Instability metric** | `Choreo.Dependency.instability/1`, `Choreo.UML.coupling_metrics/1` |

---

## Implementation notes

* Most path and impact analyses work on a **simple graph** view produced by `to_simple_graph/1` or `Yog.Multi.to_simple_graph/1`, which collapses parallel edges.
* **Topological-order DP** (`Choreo.Internal.compute_dp/3`) is the shared implementation for longest/critical path calculations across Dataflow, Dependency, ERD, Workflow, and Planner.
* **Transitive reduction** is implemented centrally in `Choreo.Internal.transitive_reduction/1` and reused by Dependency, ERD, and UML.
* **BFS reachability** (`Choreo.Internal.bfs_reachable/2`) is the shared primitive for downstream/upstream impact analysis across nearly all diagram types.
