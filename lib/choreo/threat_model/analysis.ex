defmodule Choreo.ThreatModel.Analysis do
  @moduledoc """
  STRIDE threat analysis for `Choreo.ThreatModel`.

  Automatically generates threats based on element types, data-flow
  topology, and trust-boundary crossings.

  ## STRIDE categories

  | Category | Targets | Question |
  |----------|---------|----------|
  | **S**poofing | External entities, processes | Can someone impersonate this? |
  | **T**ampering | Processes, data stores, flows | Can data be modified? |
  | **R**epudiation | External entities, processes | Can actions be denied? |
  | **I**nformation Disclosure | Processes, data stores, flows | Can data leak? |
  | **D**enial of Service | Processes, data stores, flows | Can this be overwhelmed? |
  | **E**levation of Privilege | Processes, data stores | Can an attacker gain access? |

  ## Further reading

    * [STRIDE Model (Microsoft)](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)
    * [STRIDE-per-Element](https://shostack.org/resources/stride-per-element)
    * [OWASP Threat Modeling](https://owasp.org/www-community/Threat_Modeling)
  """

  alias Choreo.ThreatModel

  defmodule Rule do
    @moduledoc """
    Extensible callback protocols for defining organizational custom threat metrics.
    """
    @callback threats_for_element(ThreatModel.t(), Yog.node_id(), map()) :: [map()]
    @callback threats_for_flow(ThreatModel.t(), Yog.node_id(), Yog.node_id()) :: [map()]
    @optional_callbacks threats_for_element: 3, threats_for_flow: 3
  end

  @doc """
  Generates STRIDE threats for every element and data flow in the model.

  Returns a list of threat structs:

      %{
        id: String.t(),
        category: :spoofing | :tampering | :repudiation | :information_disclosure | :denial_of_service | :elevation_of_privilege,
        target: Yog.node_id(),
        description: String.t(),
        severity: :low | :medium | :high | :critical,
        mitigation: String.t()
      }

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_trust_boundary("internet", level: 0)
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app", level: 2)
      ...>   |> Choreo.ThreatModel.add_external_entity(:user, boundary: "internet")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api)
      iex> threats = Choreo.ThreatModel.Analysis.stride_threats(model)
      iex> Enum.any?(threats, & &1.category == :spoofing)
      true
      iex> Enum.any?(threats, & &1.target == :user)
      true
      iex> Enum.any?(threats, & match?({:user, :api}, &1.target))
      true

  This analysis answers the question: "What threats exist in my architecture?"
  """
  @spec stride_threats(ThreatModel.t(), keyword()) :: [
          %{
            id: String.t(),
            category: atom(),
            target: Yog.node_id() | {Yog.node_id(), Yog.node_id()},
            description: String.t(),
            severity: :low | :medium | :high | :critical,
            mitigation: String.t()
          }
        ]
  def stride_threats(%ThreatModel{} = model, opts \\ []) do
    custom_rules = Keyword.get(opts, :rules, [])

    element_threats =
      model.graph.nodes
      |> Enum.flat_map(fn {id, data} ->
        base = threats_for_element(model, id, data)

        custom =
          Enum.flat_map(custom_rules, fn rule ->
            if function_exported?(rule, :threats_for_element, 3) do
              rule.threats_for_element(model, id, data)
            else
              []
            end
          end)

        base ++ custom
      end)

    flow_threats =
      model
      |> ThreatModel.edges_with_meta()
      |> Enum.flat_map(fn {from, to, _label, meta} ->
        base = threats_for_flow(model, from, to, meta)

        custom =
          Enum.flat_map(custom_rules, fn rule ->
            if function_exported?(rule, :threats_for_flow, 3) do
              rule.threats_for_flow(model, from, to)
            else
              []
            end
          end)

        base ++ custom
      end)

    (element_threats ++ flow_threats)
    |> Enum.with_index(1)
    |> Enum.map(fn {threat, idx} -> Map.put(threat, :id, "T#{idx}") end)
  end

  @doc """
  Summarises threats by STRIDE category and severity.

  Returns a map of `%{category => %{severity => count}}` plus totals.
  Useful for dashboards and executive reporting.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      iex> summary = Choreo.ThreatModel.Analysis.threat_summary(model)
      iex> summary.total > 0
      true
      iex> is_map(summary.by_category)
      true
      iex> is_map(summary.by_severity)
      true

  This analysis answers the question: "How are threats distributed by category and severity?"
  """
  @spec threat_summary(ThreatModel.t()) :: %{
          by_category: %{atom() => %{atom() => non_neg_integer()}},
          by_severity: %{atom() => non_neg_integer()},
          total: non_neg_integer()
        }
  def threat_summary(%ThreatModel{} = model) do
    threats = stride_threats(model)

    by_category =
      threats
      |> Enum.group_by(& &1.category)
      |> Enum.into(%{}, fn {cat, items} ->
        severity_counts =
          items
          |> Enum.group_by(& &1.severity)
          |> Enum.into(%{}, fn {sev, list} -> {sev, length(list)} end)

        {cat, severity_counts}
      end)

    by_severity =
      threats
      |> Enum.group_by(& &1.severity)
      |> Enum.into(%{}, fn {sev, items} -> {sev, length(items)} end)

    %{
      by_category: by_category,
      by_severity: by_severity,
      total: length(threats)
    }
  end

  @doc """
  Returns all data flows that cross a trust boundary.

  Each result is `{from, to, from_boundary, to_boundary}`.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_trust_boundary("internet", level: 0)
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app", level: 2)
      ...>   |> Choreo.ThreatModel.add_external_entity(:user, boundary: "internet")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api)
      iex> flows = Choreo.ThreatModel.Analysis.cross_boundary_flows(model)
      iex> length(flows)
      1
      iex> Enum.any?(flows, fn {from, to, _, _} -> from == :user and to == :api end)
      true

  This analysis answers the question: "Which data flows cross a trust boundary?"
  """
  @spec cross_boundary_flows(ThreatModel.t()) :: [
          {Yog.node_id(), Yog.node_id(), String.t() | nil, String.t() | nil}
        ]
  def cross_boundary_flows(%ThreatModel{} = model) do
    model
    |> ThreatModel.flows()
    |> Enum.filter(fn {from, to, _label} -> ThreatModel.crosses_boundary?(model, from, to) end)
    |> Enum.map(fn {from, to, _label} ->
      {from, to, ThreatModel.boundary_of(model, from), ThreatModel.boundary_of(model, to)}
    end)
  end

  @doc """
  Returns data stores that are reachable from an external entity
  (directly or indirectly).

  These are high-value targets because they contain data at rest and
  are exposed to untrusted input.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_external_entity(:user)
      ...>   |> Choreo.ThreatModel.add_process(:api)
      ...>   |> Choreo.ThreatModel.add_data_store(:db)
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api)
      ...>   |> Choreo.ThreatModel.data_flow(:api, :db)
      iex> Choreo.ThreatModel.Analysis.exposed_data_stores(model)
      [:db]

  This analysis answers the question: "Which data stores are reachable from external entities?"
  """
  @spec exposed_data_stores(ThreatModel.t()) :: [Yog.node_id()]
  def exposed_data_stores(%ThreatModel{} = model) do
    externals = ThreatModel.elements_of_type(model, :external_entity)
    simple_graph = ThreatModel.to_simple_graph(model)

    reachable =
      externals
      |> Enum.reduce(MapSet.new(), fn id, acc ->
        Choreo.Internal.bfs_reachable(simple_graph, [id]) |> MapSet.union(acc)
      end)

    model
    |> ThreatModel.elements_of_type(:data_store)
    |> Enum.filter(&MapSet.member?(reachable, &1))
  end

  @doc """
  Returns all paths from external entities to data stores.

  Each result is a list of node IDs representing a path from the
  internet to data at rest. These are the attack vectors that an
  adversary would follow.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_external_entity(:user)
      ...>   |> Choreo.ThreatModel.add_process(:api)
      ...>   |> Choreo.ThreatModel.add_data_store(:db)
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api)
      ...>   |> Choreo.ThreatModel.data_flow(:api, :db)
      iex> paths = Choreo.ThreatModel.Analysis.attack_paths(model)
      iex> [:user, :api, :db] in paths
      true

  This analysis answers the question: "What are the attack vectors from outside to data at rest?"
  """
  @spec attack_paths(ThreatModel.t()) :: [[Yog.node_id()]]
  def attack_paths(%ThreatModel{} = model) do
    externals = ThreatModel.elements_of_type(model, :external_entity)
    stores = ThreatModel.elements_of_type(model, :data_store) |> MapSet.new()
    simple_graph = ThreatModel.to_simple_graph(model)

    externals
    |> Enum.flat_map(fn ext ->
      dfs_all_paths(simple_graph, ext, stores, [ext], MapSet.new([ext]))
    end)
  end

  @doc """
  Returns processes that sit in low-trust boundaries but access
  high-sensitivity data stores.

  These are risky because compromised process code can leak or tamper
  with sensitive data.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_process(:api)
      ...>   |> Choreo.ThreatModel.add_data_store(:db, sensitivity: :confidential)
      ...>   |> Choreo.ThreatModel.data_flow(:api, :db)
      iex> Choreo.ThreatModel.Analysis.high_risk_processes(model)
      [:api]

  This analysis answers the question: "Which processes access sensitive data from low-trust zones?"
  """
  @spec high_risk_processes(ThreatModel.t()) :: [Yog.node_id()]
  def high_risk_processes(%ThreatModel{} = model) do
    processes = ThreatModel.elements_of_type(model, :process)
    data_stores = ThreatModel.elements_of_type(model, :data_store)
    simple_graph = ThreatModel.to_simple_graph(model)

    sensitive_stores =
      data_stores
      |> Enum.filter(fn id ->
        data = Map.get(model.graph.nodes, id)
        data[:sensitivity] in [:confidential, :restricted]
      end)
      |> MapSet.new()

    processes
    |> Enum.filter(fn proc ->
      reachable = Choreo.Internal.bfs_reachable(simple_graph, [proc])

      level = ThreatModel.trust_level(model, proc)
      low_trust = is_nil(level) || level <= 2

      not MapSet.disjoint?(reachable, sensitive_stores) and low_trust
    end)
  end

  @doc """
  Returns unencrypted data flows that cross a trust boundary.

  These are prime targets for interception and tampering.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_trust_boundary("internet", level: 0)
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app", level: 2)
      ...>   |> Choreo.ThreatModel.add_external_entity(:user, boundary: "internet")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api)
      iex> Choreo.ThreatModel.Analysis.unencrypted_boundary_flows(model)
      [{:user, :api}]

  This analysis answers the question: "Which cross-boundary flows are unencrypted?"
  """
  @spec unencrypted_boundary_flows(ThreatModel.t()) :: [{Yog.node_id(), Yog.node_id()}]
  def unencrypted_boundary_flows(%ThreatModel{} = model) do
    model
    |> ThreatModel.edges_with_meta()
    |> Enum.filter(fn {from, to, _label, meta} ->
      ThreatModel.crosses_boundary?(model, from, to) and
        meta[:encrypted] != true
    end)
    |> Enum.map(fn {from, to, _label, _meta} -> {from, to} end)
  end

  @doc """
  Validates a threat model and returns a list of issues.

  Checks for:
    * elements not assigned to a trust boundary
    * unencrypted cross-boundary flows
    * processes without privilege level
    * data stores without sensitivity classification

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app", privilege: :user)
      ...>   |> Choreo.ThreatModel.add_data_store(:db, boundary: "app", sensitivity: :internal)
      ...>   |> Choreo.ThreatModel.data_flow(:api, :db, encrypted: true)
      iex> Choreo.ThreatModel.Analysis.validate(model)
      []

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_process(:api)
      iex> issues = Choreo.ThreatModel.Analysis.validate(model)
      iex> Enum.any?(issues, fn {_sev, msg} -> String.contains?(msg, "trust boundary") end)
      true

  This analysis answers the question: "Is the threat model structurally sound?"
  """
  @spec validate(ThreatModel.t()) :: [{:error | :warning, String.t()}]
  def validate(%ThreatModel{} = model) do
    []
    |> check_missing_boundaries(model)
    |> check_unencrypted_flows(model)
    |> check_unclassified_processes(model)
    |> check_unclassified_stores(model)
  end

  # ============================================================================
  # Private helpers — STRIDE threat generation
  # ============================================================================
  defp threats_for_element(model, id, data) do
    type = data[:element_type]
    boundary = ThreatModel.boundary_of(model, id)
    level = ThreatModel.trust_level(model, id)

    base =
      case type do
        :external_entity -> external_entity_threats(id, data)
        :process -> process_threats(id, data)
        :data_store -> data_store_threats(id, data)
        _ -> []
      end

    # Elevate severity for elements in low-trust boundaries
    if boundary != nil and level != nil and level <= 1 do
      Enum.map(base, &elevate_severity/1)
    else
      base
    end
  end

  defp external_entity_threats(id, _data) do
    [
      %{
        category: :spoofing,
        target: id,
        description: "An attacker may impersonate #{id}",
        severity: :high,
        mitigation: "Authenticate all external entities (tokens, certificates, MFA)"
      },
      %{
        category: :repudiation,
        target: id,
        description: "Actions by #{id} may be denied",
        severity: :medium,
        mitigation: "Log and audit all significant actions with non-repudiation"
      }
    ]
  end

  defp process_threats(id, data) do
    privilege = data[:privilege] || :user

    base = [
      %{
        category: :spoofing,
        target: id,
        description: "An attacker may spoof or impersonate #{id}",
        severity: :medium,
        mitigation: "Validate caller identity and use strong authentication"
      },
      %{
        category: :tampering,
        target: id,
        description: "An attacker may tamper with #{id} logic or input data",
        severity: :medium,
        mitigation: "Validate all inputs; use integrity checks (signatures, hashes)"
      },
      %{
        category: :repudiation,
        target: id,
        description: "#{id} may deny performing an action",
        severity: :low,
        mitigation: "Write tamper-evident audit logs"
      },
      %{
        category: :information_disclosure,
        target: id,
        description: "Sensitive data may be exposed by #{id}",
        severity: :medium,
        mitigation: "Apply least-privilege; encrypt sensitive data in memory and logs"
      },
      %{
        category: :denial_of_service,
        target: id,
        description: "#{id} may be overwhelmed by requests",
        severity: :medium,
        mitigation: "Rate limiting, circuit breakers, autoscaling"
      }
    ]

    elevation =
      if privilege in [:admin, :system] do
        [
          %{
            category: :elevation_of_privilege,
            target: id,
            description: "An attacker may exploit #{id} to gain #{privilege} privileges",
            severity: :high,
            mitigation: "Minimize privilege surface; sandboxing; privilege separation"
          }
        ]
      else
        []
      end

    base = if privilege == :none, do: Enum.map(base, &lower_severity/1), else: base

    base ++ elevation
  end

  defp data_store_threats(id, data) do
    sensitivity = data[:sensitivity] || :internal

    base_severity =
      case sensitivity do
        :restricted -> :critical
        :confidential -> :high
        :internal -> :medium
        _ -> :low
      end

    [
      %{
        category: :tampering,
        target: id,
        description: "Data may be tampered with in #{id}",
        severity: base_severity,
        mitigation: "Access controls, integrity checks, immutable audit logs"
      },
      %{
        category: :information_disclosure,
        target: id,
        description: "Sensitive data may be leaked from #{id}",
        severity: base_severity,
        mitigation: "Encryption at rest, strict ACLs, data masking"
      },
      %{
        category: :denial_of_service,
        target: id,
        description: "#{id} may become unavailable",
        severity: :medium,
        mitigation: "Backups, replication, DDoS protection"
      },
      %{
        category: :elevation_of_privilege,
        target: id,
        description: "An attacker with read access to #{id} may escalate to write access",
        severity: base_severity,
        mitigation: "Separate read/write ACLs, role-based access, audit access patterns"
      }
    ]
  end

  defp threats_for_flow(model, from, to, meta) do
    crosses = ThreatModel.crosses_boundary?(model, from, to)
    encrypted = meta[:encrypted] == true

    base_severity = if crosses, do: :high, else: :medium

    threats =
      [
        %{
          category: :tampering,
          target: {from, to},
          description: "Data in transit between #{from} and #{to} may be tampered with",
          severity: base_severity,
          mitigation: "Use authenticated encryption (TLS 1.3, mTLS, signed payloads)"
        },
        %{
          category: :information_disclosure,
          target: {from, to},
          description: "Data in transit between #{from} and #{to} may be intercepted",
          severity: base_severity,
          mitigation: "Encrypt all data in transit; use secure key management"
        }
      ]

    # Extra threat for cross-boundary flows
    extra =
      if crosses do
        [
          %{
            category: :denial_of_service,
            target: {from, to},
            description:
              "Communication between #{from} and #{to} may be disrupted at the boundary",
            severity: :medium,
            mitigation: "Redundant paths, boundary monitoring, fail-closed design"
          }
        ]
      else
        []
      end

    # Downgrade if already encrypted
    all = threats ++ extra

    if encrypted do
      Enum.map(all, &lower_severity/1)
    else
      all
    end
  end

  defp elevate_severity(%{severity: :low} = threat), do: %{threat | severity: :medium}
  defp elevate_severity(%{severity: :medium} = threat), do: %{threat | severity: :high}
  defp elevate_severity(%{severity: :high} = threat), do: %{threat | severity: :critical}
  defp elevate_severity(threat), do: threat

  defp lower_severity(%{severity: :critical} = threat), do: %{threat | severity: :high}
  defp lower_severity(%{severity: :high} = threat), do: %{threat | severity: :medium}
  defp lower_severity(%{severity: :medium} = threat), do: %{threat | severity: :low}
  defp lower_severity(threat), do: threat

  # ============================================================================
  # Private helpers — path enumeration
  # ============================================================================

  defp dfs_all_paths(graph, current, targets, path, visited) do
    if MapSet.member?(targets, current) and length(path) > 1 do
      [Enum.reverse(path)]
    else
      successors = Yog.successors(graph, current)

      successors
      |> Enum.flat_map(fn {neighbor, _weight} ->
        if MapSet.member?(visited, neighbor) do
          []
        else
          dfs_all_paths(
            graph,
            neighbor,
            targets,
            [neighbor | path],
            MapSet.put(visited, neighbor)
          )
        end
      end)
    end
  end

  # ============================================================================
  # Private helpers — validation
  # ============================================================================

  defp check_missing_boundaries(acc, model) do
    unassigned =
      model.graph.nodes
      |> Enum.filter(fn {_id, data} -> is_nil(data[:cluster]) end)
      |> Enum.map(fn {id, _data} -> id end)

    if unassigned == [] do
      acc
    else
      [{:warning, "Elements not assigned to a trust boundary: #{inspect(unassigned)}"} | acc]
    end
  end

  defp check_unencrypted_flows(acc, model) do
    case unencrypted_boundary_flows(model) do
      [] ->
        acc

      flows ->
        flow_str =
          flows
          |> Enum.map_join(", ", fn {from, to} -> "#{from}->#{to}" end)

        [{:error, "Unencrypted cross-boundary flows: #{flow_str}"} | acc]
    end
  end

  defp check_unclassified_processes(acc, model) do
    unclassified =
      model.graph.nodes
      |> Enum.filter(fn {_id, data} ->
        data[:element_type] == :process and is_nil(data[:privilege])
      end)
      |> Enum.map(fn {id, _data} -> id end)

    if unclassified == [] do
      acc
    else
      [{:warning, "Processes without privilege level: #{inspect(unclassified)}"} | acc]
    end
  end

  defp check_unclassified_stores(acc, model) do
    unclassified =
      model.graph.nodes
      |> Enum.filter(fn {_id, data} ->
        data[:element_type] == :data_store and is_nil(data[:sensitivity])
      end)
      |> Enum.map(fn {id, _data} -> id end)

    if unclassified == [] do
      acc
    else
      [{:warning, "Data stores without sensitivity: #{inspect(unclassified)}"} | acc]
    end
  end
end
