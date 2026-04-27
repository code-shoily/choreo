defprotocol Choreo.DOT do
  @moduledoc """
  Renders a structured diagram module into a Graphviz DOT string representation.
  """
  @fallback_to_any true
  def to_dot(diagram, opts)
end
