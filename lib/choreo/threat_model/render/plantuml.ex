defmodule Choreo.ThreatModel.Render.PlantUML do
  @moduledoc """
  Generates PlantUML sequence diagrams from data flows.
  """

  alias Choreo.ThreatModel

  @doc """
  Renders the data flows in a threat model to PlantUML sequence diagram format.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = Choreo.ThreatModel.add_process(model, :api)
      iex> model = Choreo.ThreatModel.add_data_store(model, :db)
      iex> model = Choreo.ThreatModel.data_flow(model, :api, :db, label: "save")
      iex> Choreo.ThreatModel.Render.PlantUML.to_sequence(model)
      "@startuml\\napi -> db : save\\n@enduml\\n"
  """
  @spec to_sequence(ThreatModel.t()) :: String.t()
  def to_sequence(%ThreatModel{} = model) do
    flows = ThreatModel.flows(model)

    lines =
      flows
      |> Enum.map(fn {from, to, label} ->
        label = if label == "" or is_nil(label), do: "flow", else: to_string(label)
        "#{from} -> #{to} : #{label}"
      end)

    """
    @startuml
    #{Enum.join(lines, "\n")}
    @enduml
    """
  end
end
