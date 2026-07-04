defmodule Choreo.Requirement.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.Requirement` diagrams.

  Produces native `requirementDiagram` syntax with requirements, elements,
  and traceability relationships.
  """

  @doc """
  Renders a requirements diagram to Mermaid.js `requirementDiagram` syntax.

  ## Options

    * `:direction` — `:td` (default), `:lr`, `:rl`, `:bt`

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:a, id: "R1", text: "A")
      iex> mermaid = Choreo.Requirement.Render.Mermaid.to_mermaid(req)
      iex> String.contains?(mermaid, "requirementDiagram")
      true
  """
  @spec to_mermaid(Choreo.Requirement.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.Requirement{} = req, opts \\ []) do
    direction = Keyword.get(opts, :direction, :td)

    lines =
      ["requirementDiagram"]
      |> maybe_add_direction(direction)
      |> Kernel.++(render_class_defs())
      |> Kernel.++(render_requirements(req))
      |> Kernel.++(render_elements(req))
      |> Kernel.++(render_relationships(req))
      |> Kernel.++(render_risk_classes(req))
      |> List.flatten()

    Enum.join(lines, "\n") <> "\n"
  end

  # ============================================================================
  # Direction
  # ============================================================================

  defp maybe_add_direction(lines, :td), do: lines

  defp maybe_add_direction(lines, dir) when dir in [:lr, :rl, :bt] do
    [head | tail] = lines
    [head, "direction #{String.upcase(to_string(dir))}" | tail]
  end

  defp maybe_add_direction(lines, _), do: lines

  # ============================================================================
  # Class definitions for risk
  # ============================================================================

  defp render_class_defs do
    [
      "classDef lowRisk fill:#22c55e",
      "classDef mediumRisk fill:#eab308",
      "classDef highRisk fill:#f97316",
      "classDef criticalRisk fill:#ef4444"
    ]
  end

  # ============================================================================
  # Requirements
  # ============================================================================

  defp render_requirements(req) do
    req.graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :requirement end)
    |> Enum.sort_by(fn {id, _data} -> to_string(id) end)
    |> Enum.map(fn {id, data} -> render_requirement(id, data) end)
  end

  defp render_requirement(id, data) do
    kind = mermaid_kind(data[:kind])
    safe_id = sanitize_id(id)
    req_id = sanitize_text(data[:id] || "")
    text = sanitize_text(data[:text] || "")
    risk = mermaid_risk(data[:risk])
    verification = mermaid_verification(data[:verification])

    [
      "#{kind} #{safe_id} {",
      "    id: #{req_id}",
      "    text: #{text}",
      "    risk: #{risk}",
      "    verifymethod: #{verification}",
      "}"
    ]
  end

  defp mermaid_kind(:functional), do: "functionalRequirement"
  defp mermaid_kind(:interface), do: "interfaceRequirement"
  defp mermaid_kind(:performance), do: "performanceRequirement"
  defp mermaid_kind(:physical), do: "physicalRequirement"
  defp mermaid_kind(:design_constraint), do: "designConstraint"
  defp mermaid_kind(_), do: "requirement"

  defp mermaid_risk(:low), do: "Low"
  defp mermaid_risk(:medium), do: "Medium"
  defp mermaid_risk(:high), do: "High"
  defp mermaid_risk(:critical), do: "High"
  defp mermaid_risk(_), do: "Medium"

  defp mermaid_verification(:analysis), do: "Analysis"
  defp mermaid_verification(:inspection), do: "Inspection"
  defp mermaid_verification(:test), do: "Test"
  defp mermaid_verification(:demonstration), do: "Demonstration"
  defp mermaid_verification(_), do: "Test"

  # ============================================================================
  # Elements (components, tests, stakeholders)
  # ============================================================================

  defp render_elements(req) do
    req.graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] in [:component, :test, :stakeholder] end)
    |> Enum.sort_by(fn {id, _data} -> to_string(id) end)
    |> Enum.map(fn {id, data} -> render_element(id, data) end)
  end

  defp render_element(id, data) do
    safe_id = sanitize_id(id)
    type = sanitize_text(data[:type] || default_element_type(data[:node_type]))
    label = sanitize_text(data[:label] || to_string(id))

    docref = data[:docref]

    body =
      if docref do
        [
          "element #{safe_id} {",
          "    type: #{type}",
          "    docref: #{sanitize_text(docref)}",
          "}"
        ]
      else
        [
          "element #{safe_id} {",
          "    type: #{type}",
          "}"
        ]
      end

    # Mermaid element blocks don't show a custom label, so add a comment
    ["%% #{label}" | body]
  end

  defp default_element_type(:component), do: "component"
  defp default_element_type(:test), do: "test"
  defp default_element_type(:stakeholder), do: "stakeholder"
  defp default_element_type(_), do: "element"

  # ============================================================================
  # Relationships
  # ============================================================================

  defp render_relationships(req) do
    req.graph.edges
    |> Enum.sort_by(fn {edge_id, _} -> edge_id end)
    |> Enum.map(fn {edge_id, {from, to, _weight}} ->
      meta = Map.get(req.edge_meta, edge_id, %{})
      type = mermaid_relation_type(meta[:type] || :traces)
      "#{sanitize_id(from)} - #{type} -> #{sanitize_id(to)}"
    end)
  end

  defp mermaid_relation_type(:depends), do: :traces

  defp mermaid_relation_type(type)
       when type in [:contains, :copies, :derives, :satisfies, :verifies, :refines, :traces],
       do: type

  defp mermaid_relation_type(_), do: :traces

  # ============================================================================
  # Risk class assignments
  # ============================================================================

  defp render_risk_classes(req) do
    req.graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :requirement end)
    |> Enum.sort_by(fn {id, _data} -> to_string(id) end)
    |> Enum.map(fn {id, data} ->
      class = risk_class(data[:risk])
      "class #{sanitize_id(id)} #{class}"
    end)
  end

  defp risk_class(:low), do: "lowRisk"
  defp risk_class(:medium), do: "mediumRisk"
  defp risk_class(:high), do: "highRisk"
  defp risk_class(:critical), do: "criticalRisk"
  defp risk_class(_), do: "mediumRisk"

  # ============================================================================
  # Sanitization helpers
  # ============================================================================

  defp sanitize_id(id) do
    id
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> then(fn s ->
      if s =~ ~r/^[0-9]/, do: "_" <> s, else: s
    end)
  end

  defp sanitize_text(text) do
    text = to_string(text)

    escaped =
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", " ")

    "\"#{escaped}\""
  end
end
