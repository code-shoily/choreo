defmodule Choreo.MCP do
  @moduledoc """
  A lightweight, zero-dependency MCP (Model Context Protocol) server implementation.
  Exposes system design capabilities to LLM clients via stdio transport.
  """

  require Logger

  alias Choreo.Livebook

  @protocol_version "2024-11-05"

  @doc """
  Starts the stdio loop. Configures the logger to write to standard error
  so that standard output remains clean for JSON-RPC messages.
  """
  def start do
    # Configure console backend to use standard error dynamically to prevent compiler warning
    if function_exported?(Logger, :configure_backend, 2) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Logger, :configure_backend, [:console, [device: :standard_error]])
    end

    loop()
  end

  defp loop do
    case IO.read(:line) do
      :eof ->
        :ok

      {:error, reason} ->
        Logger.error("Error reading from stdio: #{inspect(reason)}")
        :ok

      line ->
        case Jason.decode(line) do
          {:ok, request} ->
            case handle_request(request) do
              nil ->
                loop()

              response ->
                # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
                IO.puts(Jason.encode!(response))
                loop()
            end

          {:error, reason} ->
            # Best-effort parse error response when we cannot read an id
            response =
              case Jason.decode(line, keys: :strings) do
                {:ok, %{"id" => id}} ->
                  jsonrpc_error(id, -32_700, "Parse error: #{inspect(reason)}")

                _ ->
                  jsonrpc_error(nil, -32_700, "Parse error: #{inspect(reason)}")
              end

            # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
            IO.puts(Jason.encode!(response))
            loop()
        end
    end
  end

  # JSON-RPC Handlers
  @doc false
  def handle_request(%{"jsonrpc" => "2.0", "id" => id, "method" => "initialize"} = _req) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "protocolVersion" => @protocol_version,
        "capabilities" => %{
          "tools" => %{}
        },
        "serverInfo" => %{
          "name" => "choreo-mcp",
          "version" => server_version()
        }
      }
    }
  end

  @doc false
  def handle_request(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"} = _req) do
    # No response needed for notifications/initialized
    nil
  end

  @doc false
  def handle_request(%{"jsonrpc" => "2.0", "id" => id, "method" => "tools/list"} = _req) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "tools" => tools()
      }
    }
  end

  @doc false
  def handle_request(
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "method" => "tools/call",
          "params" => %{"name" => name, "arguments" => args}
        } = _req
      ) do
    {is_error, content} =
      case call_tool(name, args) do
        {:ok, text} -> {false, [%{"type" => "text", "text" => text}]}
        {:error, err} -> {true, [%{"type" => "text", "text" => err}]}
      end

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "content" => content,
        "isError" => is_error
      }
    }
  end

  @doc false
  def handle_request(%{"jsonrpc" => "2.0", "id" => id} = _req) do
    jsonrpc_error(id, -32_601, "Method not found")
  end

  @doc false
  def handle_request(_request) do
    jsonrpc_error(nil, -32_600, "Invalid Request")
  end

  defp jsonrpc_error(id, code, message) do
    error = %{
      "jsonrpc" => "2.0",
      "error" => %{
        "code" => code,
        "message" => message
      }
    }

    if id, do: Map.put(error, "id", id), else: error
  end

  # Tool definitions
  defp tools do
    [
      %{
        name: "choreo_initialize_design_notebook",
        description: """
        Initializes a new system design Livebook at the specified path.
        Pre-populates the Livebook with the core Choreo dependencies, aliases,
        and standard sections (Problem, Requirements, C4 Context, C4 Container, Tradeoffs, LLM Review).
        """,
        inputSchema: %{
          type: "object",
          required: ["path", "system_name"],
          properties: %{
            path: %{
              type: "string",
              description: "Absolute path to the new Livebook file (ends with .livemd)"
            },
            system_name: %{
              type: "string",
              description: "Clear, human-readable name of the system (e.g. Rate Limiter)"
            },
            template: %{type: "string", enum: ["minimal", "full"], default: "minimal"}
          }
        }
      },
      %{
        name: "choreo_read_design_notebook",
        description: """
        Parses an existing Choreo system design Livebook.
        Extracts structured sections, requirements, and current Choreo diagrams/code cells
        to reduce token overhead during investigation.
        Returns a JSON array of {section, content} objects.
        """,
        inputSchema: %{
          type: "object",
          required: ["path"],
          properties: %{
            path: %{type: "string", description: "Absolute path to the Livebook file"}
          }
        }
      },
      %{
        name: "choreo_update_design_section",
        description: """
        Updates or inserts content for a specific section (e.g., C4 Context, C4 Container, Tradeoffs, or Requirements)
        within the target design Livebook. Replaces existing content inside that section while preserving the rest of the notebook.
        Section matching is exact: the section_name must appear in the header.
        """,
        inputSchema: %{
          type: "object",
          required: ["path", "section_name", "content"],
          properties: %{
            path: %{type: "string", description: "Absolute path to the Livebook file"},
            section_name: %{
              type: "string",
              description: "The header of the section to target (case-insensitive)"
            },
            content: %{
              type: "string",
              description:
                "New content (markdown or Elixir code blocks) to replace the section body"
            }
          }
        }
      },
      %{
        name: "choreo_verify_design",
        description: """
        Extracts and evaluates all Elixir code blocks in the target system design Livebook.
        Verifies syntax correctness, module availability, and Choreo runtime behavior,
        returning any warnings or design issues.
        """,
        inputSchema: %{
          type: "object",
          required: ["path"],
          properties: %{
            path: %{type: "string", description: "Absolute path to the Livebook file"}
          }
        }
      }
    ]
  end

  # Tool Handlers
  defp call_tool(
         "choreo_initialize_design_notebook",
         %{"path" => path, "system_name" => system_name} = args
       ) do
    template = Map.get(args, "template", "minimal")
    content = get_template(system_name, template)

    case File.mkdir_p(Path.dirname(path)) do
      :ok ->
        case File.write(path, content) do
          :ok -> {:ok, "Successfully initialized system design Livebook at #{path}"}
          {:error, reason} -> {:error, "Failed to write Livebook: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to create directory: #{inspect(reason)}"}
    end
  end

  defp call_tool("choreo_read_design_notebook", %{"path" => path}) do
    case File.read(path) do
      {:ok, content} ->
        sections = Livebook.parse_sections(content)
        {:ok, Jason.encode!(sections, pretty: true)}

      {:error, reason} ->
        {:error, "Failed to read Livebook: #{inspect(reason)}"}
    end
  end

  defp call_tool("choreo_update_design_section", %{
         "path" => path,
         "section_name" => section_name,
         "content" => new_content
       }) do
    case File.read(path) do
      {:ok, current_content} ->
        case replace_section_content(current_content, section_name, new_content) do
          {:ok, updated_content} ->
            case File.write(path, updated_content) do
              :ok -> {:ok, "Successfully updated section '#{section_name}' in #{path}"}
              {:error, reason} -> {:error, "Failed to save updates: #{inspect(reason)}"}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, "Failed to read Livebook: #{inspect(reason)}"}
    end
  end

  defp call_tool("choreo_verify_design", %{"path" => path}) do
    case File.read(path) do
      {:ok, content} ->
        blocks = Livebook.extract_elixir_blocks(content)

        case Livebook.evaluate_blocks(blocks) do
          :ok ->
            {:ok,
             "All Elixir blocks evaluated successfully! Verified #{length(blocks)} code blocks."}

          {:error, exception, stacktrace} ->
            {:error, "Evaluation failed:\n#{Exception.format(:error, exception, stacktrace)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read Livebook: #{inspect(reason)}"}
    end
  end

  defp call_tool(name, _) do
    {:error, "Tool '#{name}' is not implemented"}
  end

  # Helper to construct design notebook template
  defp get_template(system_name, "full") do
    """
    # System Design: #{system_name}

    ```elixir
    Mix.install([
      {:choreo, path: Path.expand("../..", __DIR__), force: true},
      {:kino_vizjs, "~> 0.9.0"}
    ])

    alias Choreo.C4
    alias Choreo.Dataflow
    alias Choreo.ERD
    alias Choreo.Requirement
    alias Choreo.ThreatModel
    alias Choreo.Workflow
    ```

    ## 1. Problem Statement

    *Define the core problem the system is designed to solve.*

    ## 2. Requirements

    ### Functional
    *   Requirement 1
    *   Requirement 2

    ### Non-Functional
    *   Latency/throughput goals
    *   Availability & Consistency SLA

    ## 3. Assumptions and Constraints

    *   Scale assumptions (e.g. DAU, writes/sec)
    *   Resource limits

    ## 4. C4 System Context

    ```elixir
    # Draw L1 C4 Context diagram here using Choreo.C4
    ```

    ## 5. C4 Container View

    ```elixir
    # Draw L2 C4 Container diagram here using Choreo.C4
    ```

    ## 6. Core Dataflow

    ```elixir
    # Draw Dataflow pipelines here using Choreo.Dataflow
    ```

    ## 7. Data Model / ERD

    ```elixir
    # Draw Database ERD here using Choreo.ERD
    ```

    ## 8. Threat Model

    ```elixir
    # Analyze security risks here using Choreo.ThreatModel
    ```

    ## 9. Tradeoffs

    *Compare choices (e.g. SQL vs NoSQL, sync vs async)*

    ## 10. LLM Review Prompt

    Use this Livebook as the source of truth. Review the design for:
    - scalability bottlenecks
    - single points of failure
    - security and abuse cases
    """
  end

  defp get_template(system_name, _minimal) do
    """
    # System Design: #{system_name}

    ```elixir
    Mix.install([
      {:choreo, path: Path.expand("../..", __DIR__), force: true},
      {:kino_vizjs, "~> 0.9.0"}
    ])

    alias Choreo.C4
    alias Choreo.Dataflow
    alias Choreo.ERD
    alias Choreo.Requirement
    alias Choreo.ThreatModel
    alias Choreo.Workflow
    ```

    ## 1. Problem Statement

    *Define the core problem the system is designed to solve.*

    ## 2. Requirements

    *   Requirement 1
    *   Requirement 2

    ## 3. Assumptions and Constraints

    *   Scale assumptions
    *   Resource limits

    ## 4. C4 System Context

    ```elixir
    # Draw L1 C4 Context diagram here using Choreo.C4
    ```

    ## 5. C4 Container View

    ```elixir
    # Draw L2 C4 Container diagram here using Choreo.C4
    ```

    ## 6. Tradeoffs

    *Compare choices (e.g. SQL vs NoSQL, sync vs async)*

    ## 7. LLM Review Prompt

    Use this Livebook as the source of truth. Review the design for:
    - scalability bottlenecks
    - single points of failure
    - security and abuse cases
    """
  end

  # Helper to find and replace section body content using exact header matching.
  defp replace_section_content(current_content, section_name, new_content) do
    lines = String.split(current_content, "\n")
    target = String.downcase(String.trim(section_name))

    result =
      Enum.reduce_while(lines, {:finding, []}, fn line, {state, acc} ->
        is_header = String.starts_with?(line, "#")

        case {state, is_header} do
          {:finding, true} ->
            normalized_header = line |> String.downcase() |> String.trim()

            # Match the requested section name against the full header text,
            # not a substring, so "Requirements" does not match
            # "Non-Functional Requirements".
            header_without_prefix =
              normalized_header
              |> String.trim_leading("#")
              |> String.trim()
              |> String.replace(~r/^\d+\.\s*/, "")

            if header_without_prefix == target do
              {:cont, {:skipping, [line | acc]}}
            else
              {:cont, {:finding, [line | acc]}}
            end

          {:finding, false} ->
            {:cont, {:finding, [line | acc]}}

          {:skipping, true} ->
            # We reached the next section header. Stop skipping, insert new content, and read the rest.
            acc = [line, new_content | acc]
            {:cont, {:done, acc}}

          {:skipping, false} ->
            # Keep skipping lines in the targeted section
            {:cont, {:skipping, acc}}

          {:done, _} ->
            {:cont, {:done, [line | acc]}}
        end
      end)

    case result do
      {:done, acc} ->
        {:ok, acc |> Enum.reverse() |> Enum.join("\n")}

      {:skipping, acc} ->
        # The targeted section was the last section of the file
        {:ok, [new_content | acc] |> Enum.reverse() |> Enum.join("\n")}

      {:finding, _} ->
        {:error, "Section '#{section_name}' not found in the notebook"}
    end
  end

  defp server_version do
    Mix.Project.config()[:version] || "0.0.0"
  rescue
    _ -> "0.0.0"
  end
end
