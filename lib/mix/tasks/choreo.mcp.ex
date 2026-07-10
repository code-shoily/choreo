defmodule Mix.Tasks.Choreo.Mcp do
  use Mix.Task

  @shortdoc "Starts the Choreo MCP stdio server for system design"
  @moduledoc """
  Starts the lightweight, zero-dependency MCP stdio server for Choreo.

  Run this task via:
      mix choreo.mcp
  """

  @impl Mix.Task
  def run(_args) do
    # Start Choreo application and dependencies
    Mix.Task.run("app.start")

    # Start the MCP stdio server loop
    Choreo.MCP.start()
  end
end
