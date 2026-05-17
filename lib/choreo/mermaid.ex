defprotocol Choreo.Mermaid do
  @moduledoc """
  Renders a structured diagram module into a Mermaid.js string representation.

  Mermaid is a JavaScript-based diagramming tool supported natively in
  GitHub, GitLab, Notion, and many other platforms.

  ## Supported diagram types

  All `Choreo` diagram modules implement this protocol:

      mermaid = Choreo.to_mermaid(system)

  The output can be embedded in Markdown:

  ````markdown
  ```mermaid
  <%= mermaid %>
  ```
  ````
  """
  @fallback_to_any true
  def to_mermaid(diagram, opts)
end
