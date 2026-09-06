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
    @callback threats_for_flow(ThreatModel.t(), Yog.node_id(), Yog.node_id(), map()) :: [map()]
    @optional_callbacks threats_for_element: 3, threats_for_flow: 4
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

  ## Options

    * `:rules` — list of modules implementing `Choreo.ThreatModel.Analysis.Rule`

  > ### ID ordering
  > Threat IDs (`T1`, `T2`, ...) are assigned in element-iteration order
  > followed by flow-iteration order. Custom rule threats that already have
  > an `:id` field keep their original ID; only auto-generated threats are
  > numbered.

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
            mitigation: String.t(),
            mitigated?: boolean(),
            controls: [atom()],
            owasp: String.t()
          }
        ]
  def stride_threats(%ThreatModel{} = model, opts \\ []) do
    custom_rules = Keyword.get(opts, :rules, [])

    element_threats =
      model.graph.nodes
      |> Enum.flat_map(fn {id, data} ->
        controls = data[:controls] || []
        base = threats_for_element(model, id, data)

        custom =
          Enum.flat_map(custom_rules, fn rule ->
            if function_exported?(rule, :threats_for_element, 3) do
              rule.threats_for_element(model, id, data)
            else
              []
            end
          end)

        (base ++ custom)
        |> Enum.map(&decorate_threat(&1, controls, data))
      end)

    flow_threats =
      model
      |> ThreatModel.edges_with_meta()
      |> Enum.flat_map(fn {from, to, _label, meta} ->
        controls = meta[:controls] || []
        base = default_threats_for_flow(model, from, to, meta)

        custom =
          Enum.flat_map(custom_rules, fn rule ->
            if function_exported?(rule, :threats_for_flow, 4) do
              rule.threats_for_flow(model, from, to, meta)
            else
              []
            end
          end)

        (base ++ custom)
        |> Enum.map(&decorate_threat(&1, controls, meta))
      end)

    (element_threats ++ flow_threats)
    |> Enum.with_index(1)
    |> Enum.map(fn {threat, idx} -> Map.put_new(threat, :id, "T#{idx}") end)
    |> maybe_filter_unmitigated(opts)
    |> maybe_filter_category(opts)
    |> maybe_filter_severity(opts)
  end

  @doc """
  Returns only unmitigated threats.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      ...>   |> Choreo.ThreatModel.add_process(:api)
      iex> threats = Choreo.ThreatModel.Analysis.unmitigated_threats(model)
      iex> Enum.all?(threats, &(!&1.mitigated?))
      true
  """
  @spec unmitigated_threats(ThreatModel.t(), keyword()) :: [map()]
  def unmitigated_threats(%ThreatModel{} = model, opts \\ []) do
    stride_threats(model, Keyword.put(opts, :only_unmitigated, true))
  end

  @doc """
  Returns threats targeting a specific element or flow.

  ## Options

    * `:include_flows` — boolean, whether to include flows connected to `target` (default: `true`)

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      ...>   |> Choreo.ThreatModel.add_process(:api)
      ...>   |> Choreo.ThreatModel.add_data_store(:db)
      ...>   |> Choreo.ThreatModel.data_flow(:api, :db)
      iex> api_threats = Choreo.ThreatModel.Analysis.threats_for(model, :api, include_flows: false)
      iex> Enum.all?(api_threats, &(&1.target == :api))
      true
  """
  @spec threats_for(ThreatModel.t(), Yog.node_id() | {Yog.node_id(), Yog.node_id()}, keyword()) ::
          [map()]
  def threats_for(%ThreatModel{} = model, target, opts \\ []) do
    include_flows = Keyword.get(opts, :include_flows, true)
    threats = stride_threats(model, opts)

    Enum.filter(threats, fn t ->
      case t.target do
        ^target -> true
        {^target, _} when include_flows -> true
        {_, ^target} when include_flows -> true
        _ -> false
      end
    end)
  end

  @doc """
  Identifies external entry points entering trusted zones.

  Returns a list of entry point maps with `:source`, `:target`, `:from_boundary`,
  `:to_boundary`, `:authenticated`, `:encrypted`, `:label`, and `:controls`.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      ...>   |> Choreo.ThreatModel.add_trust_boundary("internet", level: 0)
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app", level: 2)
      ...>   |> Choreo.ThreatModel.add_external_entity(:user, boundary: "internet")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api, label: "Login")
      iex> [entry] = Choreo.ThreatModel.Analysis.entry_points(model)
      iex> entry.source
      :user
      iex> entry.target
      :api
  """
  @spec entry_points(ThreatModel.t()) :: [map()]
  def entry_points(%ThreatModel{} = model) do
    model
    |> ThreatModel.edges_with_meta()
    |> Enum.filter(fn {from, to, _label, _meta} ->
      from_data = Map.get(model.graph.nodes, from, %{})
      to_data = Map.get(model.graph.nodes, to, %{})
      from_type = from_data[:element_type]
      to_type = to_data[:element_type]
      from_level = ThreatModel.trust_level(model, from)
      to_level = ThreatModel.trust_level(model, to)
      from_boundary = ThreatModel.boundary_of(model, from)
      to_boundary = ThreatModel.boundary_of(model, to)

      cond do
        from_type == :external_entity and to_type != :external_entity ->
          true

        from_boundary != to_boundary and
          (from_level == 0 or from_boundary in ["internet", "untrusted", "public"]) and
            (to_level != 0 and to_boundary not in ["internet", "untrusted", "public"]) ->
          true

        true ->
          false
      end
    end)
    |> Enum.map(fn {from, to, label, meta} ->
      %{
        source: from,
        target: to,
        from_boundary: ThreatModel.boundary_of(model, from),
        to_boundary: ThreatModel.boundary_of(model, to),
        authenticated: meta[:authenticated] == true,
        encrypted: meta[:encrypted] == true,
        label: meta[:label] || label || "",
        controls: meta[:controls] || []
      }
    end)
  end

  @doc """
  Identifies egress exit points leaving trusted zones towards untrusted or external targets.

  Returns a list of exit point maps with `:source`, `:target`, `:from_boundary`,
  `:to_boundary`, `:authenticated`, `:encrypted`, `:label`, and `:controls`.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      ...>   |> Choreo.ThreatModel.add_trust_boundary("internet", level: 0)
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app", level: 2)
      ...>   |> Choreo.ThreatModel.add_external_entity(:webhook, boundary: "internet")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      ...>   |> Choreo.ThreatModel.data_flow(:api, :webhook, label: "Notify")
      iex> [exit_point] = Choreo.ThreatModel.Analysis.exit_points(model)
      iex> exit_point.source
      :api
      iex> exit_point.target
      :webhook
  """
  @spec exit_points(ThreatModel.t()) :: [map()]
  def exit_points(%ThreatModel{} = model) do
    model
    |> ThreatModel.edges_with_meta()
    |> Enum.filter(fn {from, to, _label, _meta} ->
      from_data = Map.get(model.graph.nodes, from, %{})
      to_data = Map.get(model.graph.nodes, to, %{})
      from_type = from_data[:element_type]
      to_type = to_data[:element_type]
      from_level = ThreatModel.trust_level(model, from)
      to_level = ThreatModel.trust_level(model, to)
      from_boundary = ThreatModel.boundary_of(model, from)
      to_boundary = ThreatModel.boundary_of(model, to)

      cond do
        from_type != :external_entity and to_type == :external_entity ->
          true

        from_boundary != to_boundary and
          (to_level == 0 or to_boundary in ["internet", "untrusted", "public"]) and
            (from_level != 0 and from_boundary not in ["internet", "untrusted", "public"]) ->
          true

        true ->
          false
      end
    end)
    |> Enum.map(fn {from, to, label, meta} ->
      %{
        source: from,
        target: to,
        from_boundary: ThreatModel.boundary_of(model, from),
        to_boundary: ThreatModel.boundary_of(model, to),
        authenticated: meta[:authenticated] == true,
        encrypted: meta[:encrypted] == true,
        label: meta[:label] || label || "",
        controls: meta[:controls] || []
      }
    end)
  end

  @doc """
  Computes the downstream blast radius if `element_id` is compromised.

  Returns a map detailing reachable nodes, affected data stores, affected boundaries,
  maximum data sensitivity exposed, and qualitative risk rating.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      ...>   |> Choreo.ThreatModel.add_process(:api)
      ...>   |> Choreo.ThreatModel.add_data_store(:db, sensitivity: :restricted)
      ...>   |> Choreo.ThreatModel.data_flow(:api, :db)
      iex> radius = Choreo.ThreatModel.Analysis.blast_radius(model, :api)
      iex> radius.max_sensitivity
      :restricted
      iex> radius.risk_level
      :critical
      iex> radius.affected_stores
      [:db]
  """
  @spec blast_radius(ThreatModel.t(), Yog.node_id()) :: %{
          element: Yog.node_id(),
          reachable_nodes: [Yog.node_id()],
          affected_stores: [Yog.node_id()],
          affected_boundaries: [String.t()],
          max_sensitivity: atom() | nil,
          risk_level: atom()
        }
  def blast_radius(%ThreatModel{} = model, element_id) do
    simple_graph = ThreatModel.to_simple_graph(model)
    all_reachable = Choreo.Internal.bfs_reachable(simple_graph, [element_id])
    downstream = MapSet.delete(all_reachable, element_id) |> MapSet.to_list() |> Enum.sort()

    affected_stores =
      downstream
      |> Enum.filter(fn id ->
        data = Map.get(model.graph.nodes, id, %{})
        data[:element_type] == :data_store
      end)
      |> Enum.sort()

    affected_boundaries =
      [element_id | downstream]
      |> Enum.map(&ThreatModel.boundary_of(model, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    sensitivities =
      affected_stores
      |> Enum.map(fn id ->
        data = Map.get(model.graph.nodes, id, %{})
        data[:sensitivity]
      end)
      |> Enum.reject(&is_nil/1)

    max_sensitivity =
      cond do
        :restricted in sensitivities -> :restricted
        :confidential in sensitivities -> :confidential
        :internal in sensitivities -> :internal
        :public in sensitivities -> :public
        true -> nil
      end

    risk_level =
      cond do
        max_sensitivity == :restricted -> :critical
        max_sensitivity == :confidential -> :high
        max_sensitivity == :internal -> :medium
        affected_stores != [] -> :medium
        downstream != [] -> :low
        true -> :none
      end

    %{
      element: element_id,
      reachable_nodes: downstream,
      affected_stores: affected_stores,
      affected_boundaries: affected_boundaries,
      max_sensitivity: max_sensitivity,
      risk_level: risk_level
    }
  end

  @doc """
  Highlights attack paths in the model by setting `:highlighted_nodes` and `:highlighted_edges`.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      ...>   |> Choreo.ThreatModel.add_external_entity(:attacker)
      ...>   |> Choreo.ThreatModel.add_process(:gateway)
      ...>   |> Choreo.ThreatModel.add_data_store(:vault)
      ...>   |> Choreo.ThreatModel.data_flow(:attacker, :gateway)
      ...>   |> Choreo.ThreatModel.data_flow(:gateway, :vault)
      iex> highlighted = Choreo.ThreatModel.Analysis.highlight_attack_paths(model)
      iex> :vault in highlighted.highlighted_nodes
      true
      iex> {:gateway, :vault} in highlighted.highlighted_edges
      true
  """
  @spec highlight_attack_paths(ThreatModel.t(), keyword()) :: ThreatModel.t()
  def highlight_attack_paths(%ThreatModel{} = model, opts \\ []) do
    paths = Keyword.get(opts, :paths) || attack_paths(model, opts)

    hl_nodes = paths |> List.flatten() |> Enum.uniq()

    hl_edges =
      paths
      |> Enum.flat_map(fn path ->
        path |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> {a, b} end)
      end)
      |> Enum.uniq()

    %{model | highlighted_nodes: hl_nodes, highlighted_edges: hl_edges}
  end

  @doc """
  Generates a GitHub Flavored Markdown threat table.

  ## Options

    * `:summary` — boolean, whether to include a summary header with risk score and counts (default: `true`)
    * All other options are passed to `stride_threats/2` (`:only_unmitigated`, `:category`, `:severity`, etc.)

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      iex> md = Choreo.ThreatModel.Analysis.to_markdown(model)
      iex> String.contains?(md, "| ID | Category | Target |")
      true
  """
  @spec to_markdown(ThreatModel.t(), keyword()) :: String.t()
  def to_markdown(%ThreatModel{} = model, opts \\ []) do
    threats = stride_threats(model, opts)
    summary? = Keyword.get(opts, :summary, true)

    summary_section =
      if summary? do
        risk = risk_score(model)
        unmitigated_count = Enum.count(threats, &(!&1.mitigated?))

        """
        ### Threat Model Summary

        - **Total Threats**: #{length(threats)}
        - **Unmitigated**: #{unmitigated_count}
        - **Risk Score**: #{risk.score} (#{risk.rating})

        """
      else
        ""
      end

    header =
      "| ID | Category | Target | Severity | Mitigated | OWASP | Mitigation |\n" <>
        "|:---|:---|:---|:---|:---:|:---|:---|\n"

    rows =
      threats
      |> Enum.map_join("\n", fn t ->
        target_str =
          case t.target do
            {from, to} -> "#{from} -> #{to}"
            id -> to_string(id)
          end

        mitigated_str = if t.mitigated?, do: "Yes", else: "No"

        category_str =
          t.category |> to_string() |> String.replace("_", " ") |> String.capitalize()

        severity_str = t.severity |> to_string() |> String.capitalize()

        "| #{t.id} | #{category_str} | `#{target_str}` | #{severity_str} | #{mitigated_str} | #{t.owasp} | #{t.mitigation} |"
      end)

    summary_section <> header <> rows <> "\n"
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
  Calculates a total risk score and qualitative risk rating for the threat model.

  Each threat's severity is mapped to a numeric score. The total score is the sum
  of all individual threat scores.

  ## Severity Weights (Default)

  The default weights ratchet up sharply (1 → 3 → 6 → 10). This maps roughly to
  qualitative severity ramps but is not directly equivalent to CVSS scoring.

    * `:low` — 1
    * `:medium` — 3
    * `:high` — 6
    * `:critical` — 10

  ## Qualitative Ratings (Default)

    * `0` — `:none`
    * `1..10` — `:low`
    * `11..30` — `:medium`
    * `31..70` — `:high`
    * `>70` — `:critical`

  ## Options

    * `:weights` — keyword list of custom severity weights (e.g., `[low: 2, medium: 4, ...]`)
    * `:only_unmitigated`, `:category`, `:severity`, and `:rules` — forwarded to `stride_threats/2`

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      iex> %{score: score, rating: rating} = Choreo.ThreatModel.Analysis.risk_score(model)
      iex> is_number(score)
      true
      iex> rating in [:none, :low, :medium, :high, :critical]
      true

  This analysis answers the question: "What is the overall security risk rating of the architecture?"
  """
  @spec risk_score(ThreatModel.t(), keyword()) :: %{score: number(), rating: atom()}
  def risk_score(%ThreatModel{} = model, opts \\ []) do
    defaults = [low: 1, medium: 3, high: 6, critical: 10]
    {weights_opt, threat_opts} = Keyword.pop(opts, :weights, [])
    weights = Keyword.merge(defaults, weights_opt)

    threats = stride_threats(model, threat_opts)

    score =
      Enum.reduce(threats, 0, fn threat, acc ->
        acc + Keyword.get(weights, threat.severity, 0)
      end)

    %{score: score, rating: risk_rating(score)}
  end

  @doc """
  Calculates residual risk after declared controls have mitigated threats.

  This is equivalent to `risk_score(model, only_unmitigated: true)` and accepts
  the same options as `risk_score/2`, including custom severity `:weights`.
  """
  @spec residual_risk_score(ThreatModel.t(), keyword()) :: %{score: number(), rating: atom()}
  def residual_risk_score(%ThreatModel{} = model, opts \\ []) do
    risk_score(model, Keyword.put(opts, :only_unmitigated, true))
  end

  @doc """
  Returns control gaps inferred from trust boundaries, data sensitivity, and privileges.

  This acts as a lightweight security-review checklist for missing controls on
  elements and data flows. Each gap includes `:target`, `:missing`, `:severity`,
  and a human-readable `:reason`.
  """
  @spec control_gaps(ThreatModel.t()) :: [map()]
  def control_gaps(%ThreatModel{} = model) do
    flow_control_gaps(model) ++ element_control_gaps(model)
  end

  @doc """
  Returns sensitive-data exfiltration paths from data stores to external entities.

  ## Options

    * `:sensitivity` - sensitivity level or list of levels to consider
      (default: `[:confidential, :restricted]`)
    * `:max_paths` - maximum paths to return
  """
  @spec exfiltration_paths(ThreatModel.t(), keyword()) :: [[Yog.node_id()]]
  def exfiltration_paths(%ThreatModel{} = model, opts \\ []) do
    sensitivity = opts |> Keyword.get(:sensitivity, [:confidential, :restricted]) |> List.wrap()
    max_paths = Keyword.get(opts, :max_paths, nil)

    sources =
      model
      |> ThreatModel.elements_of_type(:data_store)
      |> Enum.filter(fn id -> get_in(model.graph.nodes, [id, :sensitivity]) in sensitivity end)

    targets = ThreatModel.elements_of_type(model, :external_entity) |> MapSet.new()
    simple_graph = ThreatModel.to_simple_graph(model)

    paths =
      sources
      |> Enum.flat_map(fn source ->
        dfs_all_paths(simple_graph, source, targets, [source], MapSet.new([source]))
      end)

    if max_paths, do: Enum.take(paths, max_paths), else: paths
  end

  @doc """
  Summarises data flows between trust boundaries.

  Returns a map keyed by `{from_boundary, to_boundary}` with flow counts,
  encrypted/authenticated counts, unencrypted counts, max observed sensitivity,
  and the concrete flows in each boundary pair.
  """
  @spec boundary_matrix(ThreatModel.t()) :: %{
          optional({String.t() | nil, String.t() | nil}) => map()
        }
  def boundary_matrix(%ThreatModel{} = model) do
    model
    |> ThreatModel.edges_with_meta()
    |> Enum.group_by(fn {from, to, _label, _meta} ->
      {ThreatModel.boundary_of(model, from), ThreatModel.boundary_of(model, to)}
    end)
    |> Enum.into(%{}, fn {boundary_pair, flows} ->
      summaries = Enum.map(flows, &boundary_flow_summary(model, &1))
      encrypted = Enum.count(summaries, & &1.encrypted)
      authenticated = Enum.count(summaries, & &1.authenticated)

      {boundary_pair,
       %{
         flows: summaries,
         count: length(summaries),
         encrypted: encrypted,
         unencrypted: length(summaries) - encrypted,
         authenticated: authenticated,
         unauthenticated: length(summaries) - authenticated,
         max_sensitivity: summaries |> Enum.map(& &1.sensitivity) |> max_sensitivity()
       }}
    end)
  end

  @doc """
  Produces a prioritized security-review finding list.

  Findings compose validation issues, exposed stores, unencrypted boundary flows,
  high-risk processes, exfiltration paths, and control gaps into a concise list
  sorted by severity. Use `:max_findings` to cap report length.
  """
  @spec prioritized_findings(ThreatModel.t(), keyword()) :: [map()]
  def prioritized_findings(%ThreatModel{} = model, opts \\ []) do
    findings =
      validation_findings(model, opts) ++
        exposed_store_findings(model) ++
        unencrypted_flow_findings(model) ++
        high_risk_process_findings(model) ++
        exfiltration_findings(model, opts) ++
        control_gap_findings(model)

    findings
    |> Enum.sort_by(&{-severity_rank(&1.severity), to_string(&1.kind), inspect(&1.target)})
    |> Enum.with_index(1)
    |> Enum.map(fn {finding, idx} -> Map.put_new(finding, :id, "F#{idx}") end)
    |> maybe_take_findings(opts)
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

  > ### Complexity warning
  > This function enumerates every simple path from each external entity
  > to each data store. On dense graphs the number of paths grows
  > exponentially. Use `:max_paths` to cap output for large models.

  ## Options

    * `:max_paths` — maximum number of paths to return (default: unlimited)

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
  @spec attack_paths(ThreatModel.t(), keyword()) :: [[Yog.node_id()]]
  def attack_paths(%ThreatModel{} = model, opts \\ []) do
    max_paths = Keyword.get(opts, :max_paths, nil)
    externals = ThreatModel.elements_of_type(model, :external_entity)
    stores = ThreatModel.elements_of_type(model, :data_store) |> MapSet.new()
    simple_graph = ThreatModel.to_simple_graph(model)

    paths =
      externals
      |> Enum.flat_map(fn ext ->
        dfs_all_paths(simple_graph, ext, stores, [ext], MapSet.new([ext]))
      end)

    if max_paths, do: Enum.take(paths, max_paths), else: paths
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
    * direct data flows between external entities and data stores
    * sensitive data stores located in low-trust boundaries
    * trust boundaries without a `:level` (when `require_levels: true`)

  ## Options

    * `:require_levels` — boolean, whether to warn if trust boundaries lack a `:level` (default: `false`)

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app", level: 2)
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
  @spec validate(ThreatModel.t(), keyword()) :: [{:error | :warning, String.t()}]
  def validate(%ThreatModel{} = model, opts \\ []) do
    []
    |> check_missing_boundaries(model)
    |> check_unencrypted_flows(model)
    |> check_unclassified_processes(model)
    |> check_unclassified_stores(model)
    |> check_sensitive_stores_in_low_trust(model)
    |> check_direct_external_data_store_flows(model)
    |> maybe_check_missing_boundary_levels(model, opts)
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

    # Elevate severity for elements in low-trust boundaries.
    # Note: boundaries without an explicit :level never trigger elevation.
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

  defp default_threats_for_flow(model, from, to, meta) do
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
  # Private helpers — reviewer analyses
  # ============================================================================

  defp risk_rating(score) do
    cond do
      score == 0 -> :none
      score <= 10 -> :low
      score <= 30 -> :medium
      score <= 70 -> :high
      true -> :critical
    end
  end

  defp flow_control_gaps(model) do
    model
    |> ThreatModel.edges_with_meta()
    |> Enum.flat_map(fn {from, to, _label, meta} ->
      sensitivity = flow_sensitivity(model, to, meta)

      [
        encryption_gap(model, from, to, meta, sensitivity),
        authentication_gap(model, from, to, meta),
        sensitive_flow_integrity_gap(from, to, meta, sensitivity)
      ]
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp element_control_gaps(model) do
    model.graph.nodes
    |> Enum.flat_map(fn {id, data} ->
      case data[:element_type] do
        :data_store -> data_store_control_gaps(model, id, data)
        :process -> process_control_gaps(model, id, data)
        _other -> []
      end
    end)
  end

  defp encryption_gap(model, from, to, meta, sensitivity) do
    if ThreatModel.crosses_boundary?(model, from, to) and meta[:encrypted] != true do
      %{
        target: {from, to},
        missing: [:encryption_in_transit],
        severity: if(sensitivity in [:confidential, :restricted], do: :high, else: :medium),
        reason: "Data crosses a trust boundary without encrypted transport"
      }
    end
  end

  defp authentication_gap(model, from, to, meta) do
    from_data = Map.get(model.graph.nodes, from, %{})
    to_data = Map.get(model.graph.nodes, to, %{})

    entry? =
      from_data[:element_type] == :external_entity and to_data[:element_type] != :external_entity

    if entry? and meta[:authenticated] != true do
      %{
        target: {from, to},
        missing: [:authentication],
        severity: :high,
        reason: "External entry point reaches a trusted element without authentication metadata"
      }
    end
  end

  defp sensitive_flow_integrity_gap(from, to, meta, sensitivity) do
    controls = meta[:controls] || []

    if sensitivity in [:confidential, :restricted] and
         not has_control?(controls, [:integrity, :signing, :hmac, :mtls]) do
      %{
        target: {from, to},
        missing: [:integrity_protection],
        severity: if(sensitivity == :restricted, do: :high, else: :medium),
        reason: "Sensitive data flow has no explicit integrity/signing control"
      }
    end
  end

  defp data_store_control_gaps(model, id, data) do
    sensitivity = data[:sensitivity]
    controls = data[:controls] || []
    boundary = ThreatModel.boundary_of(model, id)
    level = ThreatModel.trust_level(model, id)

    [
      if sensitivity in [:confidential, :restricted] and
           not has_control?(controls, [
             :encryption_at_rest,
             :field_level_encryption,
             :kms,
             :tokenization
           ]) do
        %{
          target: id,
          missing: [:encryption_at_rest],
          severity: if(sensitivity == :restricted, do: :critical, else: :high),
          reason: "Sensitive data store lacks an explicit encryption-at-rest control"
        }
      end,
      if sensitivity in [:confidential, :restricted] and
           (level in [0, 1] or boundary in ["internet", "dmz", "public", "untrusted"]) do
        %{
          target: id,
          missing: [:trusted_boundary],
          severity: :high,
          reason: "Sensitive data store is located in a low-trust boundary"
        }
      end
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp process_control_gaps(model, id, data) do
    controls = data[:controls] || []
    privilege = data[:privilege]
    boundary = ThreatModel.boundary_of(model, id)
    level = ThreatModel.trust_level(model, id)

    [
      if privilege in [:admin, :system] and
           not has_control?(controls, [:least_privilege, :rbac, :abac]) do
        %{
          target: id,
          missing: [:least_privilege],
          severity: :high,
          reason: "Admin/system process lacks explicit least-privilege access control"
        }
      end,
      if privilege in [:admin, :system] and
           not has_control?(controls, [:audit_logging, :logging, :siem, :audit_trail]) do
        %{
          target: id,
          missing: [:audit_logging],
          severity: :medium,
          reason: "Privileged process lacks explicit audit logging control"
        }
      end,
      if (level in [0, 1] or boundary in ["internet", "dmz", "public", "untrusted"]) and
           not has_control?(controls, [:rate_limiting, :waf, :ddos_protection, :throttling]) do
        %{
          target: id,
          missing: [:edge_abuse_protection],
          severity: :medium,
          reason: "Low-trust process lacks explicit abuse-protection controls"
        }
      end
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp boundary_flow_summary(model, {from, to, label, meta}) do
    %{
      from: from,
      to: to,
      label: meta[:label] || label || "",
      encrypted: meta[:encrypted] == true,
      authenticated: meta[:authenticated] == true,
      protocol: meta[:protocol],
      sensitivity: flow_sensitivity(model, to, meta),
      controls: meta[:controls] || []
    }
  end

  defp flow_sensitivity(model, to, meta) do
    meta[:sensitivity] || get_in(model.graph.nodes, [to, :sensitivity])
  end

  defp max_sensitivity(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&sensitivity_rank/1, fn -> nil end)
  end

  defp sensitivity_rank(:restricted), do: 4
  defp sensitivity_rank(:confidential), do: 3
  defp sensitivity_rank(:internal), do: 2
  defp sensitivity_rank(:public), do: 1
  defp sensitivity_rank(_), do: 0

  defp validation_findings(model, opts) do
    model
    |> validate(opts)
    |> Enum.map(fn {severity, message} ->
      %{
        kind: :validation_issue,
        severity: if(severity == :error, do: :high, else: :medium),
        target: :model,
        title: "Threat model validation issue",
        evidence: %{message: message},
        recommendation:
          "Resolve the validation issue before using this model for review decisions."
      }
    end)
  end

  defp exposed_store_findings(model) do
    model
    |> exposed_data_stores()
    |> Enum.map(fn store ->
      sensitivity = get_in(model.graph.nodes, [store, :sensitivity])

      %{
        kind: :exposed_data_store,
        severity: severity_for_sensitivity(sensitivity, :high),
        target: store,
        title: "Data store reachable from external entity",
        evidence: %{sensitivity: sensitivity, attack_paths: attack_paths_to(model, store)},
        recommendation:
          "Review every external-to-store path for authentication, authorization, encryption, and least privilege."
      }
    end)
  end

  defp unencrypted_flow_findings(model) do
    model
    |> unencrypted_boundary_flows()
    |> Enum.map(fn {from, to} ->
      %{
        kind: :unencrypted_boundary_flow,
        severity: :high,
        target: {from, to},
        title: "Unencrypted cross-boundary data flow",
        evidence: %{
          from_boundary: ThreatModel.boundary_of(model, from),
          to_boundary: ThreatModel.boundary_of(model, to)
        },
        recommendation:
          "Use TLS/mTLS or another authenticated encryption mechanism across the boundary."
      }
    end)
  end

  defp high_risk_process_findings(model) do
    model
    |> high_risk_processes()
    |> Enum.map(fn process ->
      %{
        kind: :high_risk_process,
        severity: :high,
        target: process,
        title: "Low-trust process can reach sensitive data",
        evidence: blast_radius(model, process),
        recommendation:
          "Reduce privilege, add authorization checks, and isolate sensitive downstream access."
      }
    end)
  end

  defp exfiltration_findings(model, opts) do
    model
    |> exfiltration_paths(opts)
    |> Enum.map(fn path ->
      %{
        kind: :exfiltration_path,
        severity: :high,
        target: List.first(path),
        title: "Sensitive data can flow to an external entity",
        evidence: %{path: path},
        recommendation:
          "Validate outbound data minimization, consent, logging, and third-party contracts on this path."
      }
    end)
  end

  defp control_gap_findings(model) do
    model
    |> control_gaps()
    |> Enum.map(fn gap ->
      %{
        kind: :control_gap,
        severity: gap.severity,
        target: gap.target,
        title: "Missing security control",
        evidence: gap,
        recommendation:
          "Add or document the missing controls: #{Enum.map_join(gap.missing, ", ", &to_string/1)}."
      }
    end)
  end

  defp attack_paths_to(model, store) do
    model
    |> attack_paths()
    |> Enum.filter(&(List.last(&1) == store))
  end

  defp severity_for_sensitivity(:restricted, _default), do: :critical
  defp severity_for_sensitivity(:confidential, _default), do: :high
  defp severity_for_sensitivity(:internal, _default), do: :medium
  defp severity_for_sensitivity(_other, default), do: default

  defp severity_rank(:critical), do: 4
  defp severity_rank(:high), do: 3
  defp severity_rank(:medium), do: 2
  defp severity_rank(:low), do: 1
  defp severity_rank(_), do: 0

  defp maybe_take_findings(findings, opts) do
    case Keyword.get(opts, :max_findings) do
      count when is_integer(count) and count >= 0 -> Enum.take(findings, count)
      _other -> findings
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

  defp check_sensitive_stores_in_low_trust(acc, model) do
    stores = ThreatModel.elements_of_type(model, :data_store)

    issues =
      stores
      |> Enum.filter(fn id ->
        data = Map.get(model.graph.nodes, id, %{})
        level = ThreatModel.trust_level(model, id)
        boundary = ThreatModel.boundary_of(model, id)

        data[:sensitivity] in [:confidential, :restricted] and
          ((is_integer(level) and level <= 1) or
             boundary in ["internet", "dmz", "public", "untrusted"])
      end)
      |> Enum.map(fn id ->
        boundary = ThreatModel.boundary_of(model, id) || "none"
        {:warning, "Sensitive data store `#{id}` sits in low-trust boundary `#{boundary}`"}
      end)

    issues ++ acc
  end

  defp check_direct_external_data_store_flows(acc, model) do
    direct_flows =
      model
      |> ThreatModel.edges_with_meta()
      |> Enum.filter(fn {from, to, _label, _meta} ->
        from_data = Map.get(model.graph.nodes, from, %{})
        to_data = Map.get(model.graph.nodes, to, %{})
        from_type = from_data[:element_type]
        to_type = to_data[:element_type]

        (from_type == :external_entity and to_type == :data_store) or
          (from_type == :data_store and to_type == :external_entity)
      end)
      |> Enum.map(fn {from, to, _label, _meta} ->
        {:error,
         "Direct data flow between external entity and data store: #{from}->#{to} (must mediate through a process)"}
      end)

    direct_flows ++ acc
  end

  defp maybe_check_missing_boundary_levels(acc, model, opts) do
    if Keyword.get(opts, :require_levels, false) do
      missing =
        model.clusters
        |> Enum.filter(fn {_id, data} -> is_nil(data[:level]) end)
        |> Enum.map(fn {id, _data} -> String.replace_prefix(id, "cluster_", "") end)

      if missing == [] do
        acc
      else
        [{:warning, "Trust boundaries without a `:level`: #{inspect(missing)}"} | acc]
      end
    else
      acc
    end
  end

  # ============================================================================
  # Private helpers — Threat filtering and decoration
  # ============================================================================

  defp decorate_threat(threat, controls, meta_or_data) do
    threat
    |> Map.put_new(:controls, controls)
    |> Map.put_new(:owasp, owasp_mapping(threat.category))
    |> Map.put_new_lazy(:mitigated?, fn ->
      threat_mitigated?(threat.category, threat.target, controls, meta_or_data)
    end)
  end

  defp owasp_mapping(:spoofing), do: "A07:2021-Identification and Authentication Failures"
  defp owasp_mapping(:tampering), do: "A08:2021-Software and Data Integrity Failures"
  defp owasp_mapping(:repudiation), do: "A09:2021-Security Logging and Monitoring Failures"
  defp owasp_mapping(:information_disclosure), do: "A02:2021-Cryptographic Failures"
  defp owasp_mapping(:denial_of_service), do: "A04:2021-Insecure Design"
  defp owasp_mapping(:elevation_of_privilege), do: "A01:2021-Broken Access Control"
  defp owasp_mapping(_), do: "A04:2021-Insecure Design"

  defp threat_mitigated?(category, {_from, _to}, controls, meta) do
    case category do
      :tampering ->
        meta[:encrypted] == true or
          has_control?(controls, [
            :tls,
            :mtls,
            :https,
            :encryption,
            :encrypted,
            :ipsec,
            :vpn,
            :signing,
            :hmac,
            :integrity,
            :tampering
          ])

      :information_disclosure ->
        meta[:encrypted] == true or
          has_control?(controls, [:tls, :mtls, :https, :encryption, :encrypted, :ipsec, :vpn])

      :spoofing ->
        meta[:authenticated] == true or
          has_control?(controls, [
            :auth,
            :authentication,
            :mfa,
            :jwt,
            :oauth,
            :tokens,
            :mtls,
            :certificates
          ])

      :denial_of_service ->
        has_control?(controls, [
          :rate_limiting,
          :waf,
          :circuit_breaker,
          :ddos_protection,
          :throttling
        ])

      _ ->
        false
    end
  end

  defp threat_mitigated?(category, _target_id, controls, _data) do
    case category do
      :spoofing ->
        has_control?(controls, [
          :auth,
          :authentication,
          :mfa,
          :jwt,
          :oauth,
          :saml,
          :sso,
          :tokens,
          :certificates,
          :mtls,
          :signature
        ])

      :tampering ->
        has_control?(controls, [
          :input_validation,
          :schema_validation,
          :sanitization,
          :signing,
          :hmac,
          :integrity,
          :waf
        ])

      :repudiation ->
        has_control?(controls, [
          :audit_logging,
          :logging,
          :siem,
          :tamper_evident_logging,
          :audit_trail,
          :append_only_log
        ])

      :information_disclosure ->
        has_control?(controls, [
          :encryption_at_rest,
          :field_level_encryption,
          :kms,
          :acls,
          :data_masking,
          :tokenization,
          :least_privilege,
          :memory_safe,
          :sandbox
        ])

      :denial_of_service ->
        has_control?(controls, [
          :rate_limiting,
          :waf,
          :circuit_breaker,
          :ddos_protection,
          :autoscaling,
          :quotas,
          :throttling,
          :replication,
          :backups
        ])

      :elevation_of_privilege ->
        has_control?(controls, [
          :least_privilege,
          :rbac,
          :abac,
          :privilege_separation,
          :sandboxing,
          :mfa
        ])

      _ ->
        false
    end
  end

  defp has_control?(controls, target_controls) do
    ctrl_set = MapSet.new(controls)
    Enum.any?(target_controls, &MapSet.member?(ctrl_set, &1))
  end

  defp maybe_filter_unmitigated(threats, opts) do
    if Keyword.get(opts, :only_unmitigated, false) do
      Enum.filter(threats, &(!&1.mitigated?))
    else
      threats
    end
  end

  defp maybe_filter_category(threats, opts) do
    case Keyword.get(opts, :category) do
      nil -> threats
      categories when is_list(categories) -> Enum.filter(threats, &(&1.category in categories))
      cat when is_atom(cat) -> Enum.filter(threats, &(&1.category == cat))
    end
  end

  defp maybe_filter_severity(threats, opts) do
    case Keyword.get(opts, :severity) do
      nil -> threats
      severities when is_list(severities) -> Enum.filter(threats, &(&1.severity in severities))
      sev when is_atom(sev) -> Enum.filter(threats, &(&1.severity == sev))
    end
  end

  @doc """
  Generates a heatmap of the threat model based on threat density.

  Nodes with more threats will be colored with "hotter" colors from the
  selected palette.

  > ### Note on flow threats
  > Flow-level threats (targeting `{from, to}` tuples) are not counted
  > toward node heat since they apply to edges, not nodes. A node with
  > zero element-level threats but many high-severity flow threats may
  > appear cold in the heatmap.

  ## Options
    * `:palette` — Color palette (`:heat`, `:cool`, `:spectral`)
    * All other options are passed to `stride_threats/2`.
  """
  @spec heatmap(ThreatModel.t(), keyword()) :: ThreatModel.t()
  def heatmap(%ThreatModel{} = model, opts \\ []) do
    threats = stride_threats(model, opts)

    scores =
      threats
      |> Enum.reject(&is_tuple(&1.target))
      |> Enum.group_by(& &1.target)
      |> Enum.map(fn {id, ts} -> {id, length(ts)} end)

    # Fill in zeros for nodes with no threats
    node_ids = Map.keys(model.graph.nodes)
    zero_scores = Enum.map(node_ids, fn id -> {id, 0} end)

    final_scores =
      zero_scores
      |> Map.new()
      |> Map.merge(Map.new(scores))
      |> Map.to_list()

    Choreo.Analysis.heatmap(model, Keyword.put(opts, :scores, final_scores))
  end
end
