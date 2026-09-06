defmodule Choreo.MCPTest do
  use ExUnit.Case

  alias Choreo.MCP

  setup do
    tmp_dir = Path.expand("../../tmp/mcp_tests", __DIR__)
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "initialize handles standard lifecycle", %{tmp_dir: tmp_dir} do
    # 1. Check tools list
    req_list = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
    resp = send_request(req_list)
    assert resp["id"] == 1
    assert length(resp["result"]["tools"]) == 4
    tool_names = Enum.map(resp["result"]["tools"], & &1["name"])
    assert "choreo_initialize_design_notebook" in tool_names
    assert "choreo_read_design_notebook" in tool_names
    assert "choreo_update_design_section" in tool_names
    assert "choreo_verify_design" in tool_names

    # 2. Call initialize
    notebook_path = Path.join(tmp_dir, "test_design.livemd")

    req_init = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_initialize_design_notebook",
        "arguments" => %{
          "path" => notebook_path,
          "system_name" => "Test Database Service",
          "template" => "minimal"
        }
      }
    }

    resp_init = send_request(req_init)
    assert resp_init["id"] == 2
    assert resp_init["result"]["isError"] == false
    assert File.exists?(notebook_path)

    # 3. Read the notebook
    req_read = %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_read_design_notebook",
        "arguments" => %{"path" => notebook_path}
      }
    }

    resp_read = send_request(req_read)
    assert resp_read["id"] == 3
    assert resp_read["result"]["isError"] == false

    sections = Jason.decode!(hd(resp_read["result"]["content"])["text"])
    assert sections != []
    section_names = Enum.map(sections, & &1["section"])
    assert "## 2. Requirements" in section_names

    # 4. Update a section
    req_update = %{
      "jsonrpc" => "2.0",
      "id" => 4,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_update_design_section",
        "arguments" => %{
          "path" => notebook_path,
          "section_name" => "Requirements",
          "content" => "*   Requirement A\n*   Requirement B"
        }
      }
    }

    resp_update = send_request(req_update)
    assert resp_update["id"] == 4
    assert resp_update["result"]["isError"] == false

    # Verify update persisted
    resp_read2 = send_request(req_read)
    sections2 = Jason.decode!(hd(resp_read2["result"]["content"])["text"])
    req_section = Enum.find(sections2, &(&1["section"] == "## 2. Requirements"))
    assert req_section["content"] =~ "*   Requirement A"

    # 5. Verify the code blocks
    req_verify = %{
      "jsonrpc" => "2.0",
      "id" => 5,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_verify_design",
        "arguments" => %{"path" => notebook_path}
      }
    }

    resp_verify = send_request(req_verify)
    assert resp_verify["id"] == 5
    assert resp_verify["result"]["isError"] == false
  end

  test "initialize returns project version", %{tmp_dir: _tmp_dir} do
    req = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"}
    resp = send_request(req)

    assert resp["result"]["serverInfo"]["version"] == Mix.Project.config()[:version]
  end

  test "unknown method returns method not found" do
    req = %{"jsonrpc" => "2.0", "id" => 42, "method" => "tools/does_not_exist"}
    resp = send_request(req)

    assert resp["id"] == 42
    assert resp["error"]["code"] == -32_601
  end

  test "unknown tool returns error", %{tmp_dir: tmp_dir} do
    req = %{
      "jsonrpc" => "2.0",
      "id" => 7,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_unknown_tool",
        "arguments" => %{"path" => Path.join(tmp_dir, "missing.livemd")}
      }
    }

    resp = send_request(req)
    assert resp["id"] == 7
    assert resp["result"]["isError"] == true
    assert hd(resp["result"]["content"])["text"] =~ "not implemented"
  end

  test "update missing section returns error", %{tmp_dir: tmp_dir} do
    notebook_path = Path.join(tmp_dir, "no_section.livemd")
    File.write!(notebook_path, "# System Design: X\n\n## 1. Problem\n\nText\n")

    req = %{
      "jsonrpc" => "2.0",
      "id" => 8,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_update_design_section",
        "arguments" => %{
          "path" => notebook_path,
          "section_name" => "Nonexistent",
          "content" => "new"
        }
      }
    }

    resp = send_request(req)
    assert resp["id"] == 8
    assert resp["result"]["isError"] == true
    assert hd(resp["result"]["content"])["text"] =~ "not found"
  end

  test "verify detects runtime errors", %{tmp_dir: tmp_dir} do
    notebook_path = Path.join(tmp_dir, "bad.livemd")

    File.write!(notebook_path, """
    # Bad

    ```elixir
    raise "boom"
    ```
    """)

    req = %{
      "jsonrpc" => "2.0",
      "id" => 9,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_verify_design",
        "arguments" => %{"path" => notebook_path}
      }
    }

    resp = send_request(req)
    assert resp["id"] == 9
    assert resp["result"]["isError"] == true
    assert hd(resp["result"]["content"])["text"] =~ "boom"
  end

  test "verify ignores elixir comments as section headers", %{tmp_dir: tmp_dir} do
    notebook_path = Path.join(tmp_dir, "commented.livemd")

    File.write!(notebook_path, """
    # Test

    ## 1. Problem

    ```elixir
    # This is a comment, not a header
    x = 1 + 1
    ```

    ## 2. Tradeoffs

    Text.
    """)

    req = %{
      "jsonrpc" => "2.0",
      "id" => 10,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_read_design_notebook",
        "arguments" => %{"path" => notebook_path}
      }
    }

    resp = send_request(req)
    assert resp["id"] == 10
    assert resp["result"]["isError"] == false

    sections = Jason.decode!(hd(resp["result"]["content"])["text"])
    section_names = Enum.map(sections, & &1["section"])

    assert "## 1. Problem" in section_names
    assert "## 2. Tradeoffs" in section_names
    refute "# This is a comment, not a header" in section_names
  end

  test "update uses exact section matching", %{tmp_dir: tmp_dir} do
    notebook_path = Path.join(tmp_dir, "exact.livemd")

    File.write!(notebook_path, """
    # Test

    ## 1. Requirements

    Original.

    ## 2. Non-Functional Requirements

    Keep me.
    """)

    req = %{
      "jsonrpc" => "2.0",
      "id" => 11,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_update_design_section",
        "arguments" => %{
          "path" => notebook_path,
          "section_name" => "Requirements",
          "content" => "Updated."
        }
      }
    }

    resp = send_request(req)
    assert resp["id"] == 11
    assert resp["result"]["isError"] == false

    content = File.read!(notebook_path)
    assert content =~ "Updated."
    assert content =~ "Keep me."
  end

  test "handle_request rejects invalid jsonrpc requests" do
    req = %{"id" => 99, "method" => "tools/list"}
    resp = send_request(req)

    assert resp["error"]["code"] == -32_600
  end

  test "initialize supports full template", %{tmp_dir: tmp_dir} do
    notebook_path = Path.join(tmp_dir, "full_design.livemd")

    req_init = %{
      "jsonrpc" => "2.0",
      "id" => 12,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_initialize_design_notebook",
        "arguments" => %{
          "path" => notebook_path,
          "system_name" => "Full Distributed System",
          "template" => "full"
        }
      }
    }

    resp = send_request(req_init)
    assert resp["result"]["isError"] == false
    content = File.read!(notebook_path)
    assert content =~ "## 6. Core Dataflow"
    assert content =~ "## 8. Threat Model"
  end

  test "tools return error when target file does not exist" do
    missing_path = "/nonexistent/dir/missing.livemd"

    # read
    req_read = %{
      "jsonrpc" => "2.0",
      "id" => 13,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_read_design_notebook",
        "arguments" => %{"path" => missing_path}
      }
    }

    resp = send_request(req_read)
    assert resp["result"]["isError"] == true
    assert hd(resp["result"]["content"])["text"] =~ "Failed to read"

    # update
    req_update = %{
      "jsonrpc" => "2.0",
      "id" => 14,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_update_design_section",
        "arguments" => %{
          "path" => missing_path,
          "section_name" => "Requirements",
          "content" => "new"
        }
      }
    }

    resp = send_request(req_update)
    assert resp["result"]["isError"] == true
    assert hd(resp["result"]["content"])["text"] =~ "Failed to read"

    # verify
    req_verify = %{
      "jsonrpc" => "2.0",
      "id" => 15,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_verify_design",
        "arguments" => %{"path" => missing_path}
      }
    }

    resp = send_request(req_verify)
    assert resp["result"]["isError"] == true
    assert hd(resp["result"]["content"])["text"] =~ "Failed to read"
  end

  test "handle_request ignores notifications/initialized" do
    req = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}
    assert MCP.handle_request(req) == nil
  end

  test "mix choreo.mcp module attributes" do
    assert Mix.Task.shortdoc(Mix.Tasks.Choreo.Mcp) =~ "MCP stdio server"
  end

  test "verify returns error when code evaluation raises", %{tmp_dir: tmp_dir} do
    failing_nb = Path.join(tmp_dir, "failing.livemd")

    File.write!(failing_nb, """
    # Failing Design

    ```elixir
    raise "boom"
    ```
    """)

    req = %{
      "jsonrpc" => "2.0",
      "id" => 99,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_verify_design",
        "arguments" => %{"path" => failing_nb}
      }
    }

    resp = send_request(req)
    assert resp["result"]["isError"] == true
    assert hd(resp["result"]["content"])["text"] =~ "Evaluation failed"
  end

  test "update section when target section is the last section in the file", %{tmp_dir: tmp_dir} do
    last_sec_nb = Path.join(tmp_dir, "last_sec.livemd")

    File.write!(last_sec_nb, """
    # Design

    ## 1. Problem
    Intro text

    ## 2. Last Section
    Old text
    """)

    req = %{
      "jsonrpc" => "2.0",
      "id" => 100,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_update_design_section",
        "arguments" => %{
          "path" => last_sec_nb,
          "section_name" => "Last Section",
          "content" => "Replaced final content"
        }
      }
    }

    resp = send_request(req)
    assert resp["result"]["isError"] == false
    assert File.read!(last_sec_nb) =~ "Replaced final content"
  end

  test "handles template: full, notifications, and error scenarios", %{tmp_dir: tmp_dir} do
    # 1. Full template initialization
    full_nb = Path.join(tmp_dir, "full_design.livemd")

    req_full = %{
      "jsonrpc" => "2.0",
      "id" => 201,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_initialize_design_notebook",
        "arguments" => %{
          "path" => full_nb,
          "system_name" => "Complete System",
          "template" => "full"
        }
      }
    }

    resp_full = send_request(req_full)
    assert resp_full["result"]["isError"] == false
    assert File.read!(full_nb) =~ "## 6. Core Dataflow"

    # 2. notifications/initialized returns nil
    notif = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}
    assert MCP.handle_request(notif) == nil

    # 3. Method not found
    req_unknown = %{"jsonrpc" => "2.0", "id" => 202, "method" => "unknown/method"}
    resp_unknown = send_request(req_unknown)
    assert resp_unknown["error"]["code"] == -32_601

    # 4. Invalid request format
    resp_invalid =
      %{"invalid" => "format"}
      |> MCP.handle_request()

    assert resp_invalid["error"]["code"] == -32_600

    # 5. Unknown tool call
    req_bad_tool = %{
      "jsonrpc" => "2.0",
      "id" => 203,
      "method" => "tools/call",
      "params" => %{
        "name" => "non_existent_tool",
        "arguments" => %{}
      }
    }

    resp_bad_tool = send_request(req_bad_tool)
    assert resp_bad_tool["result"]["isError"] == true
    assert hd(resp_bad_tool["result"]["content"])["text"] =~ "not implemented"

    # 6. Read non-existent file
    req_missing_read = %{
      "jsonrpc" => "2.0",
      "id" => 204,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_read_design_notebook",
        "arguments" => %{"path" => "/path/does/not/exist.livemd"}
      }
    }

    resp_missing_read = send_request(req_missing_read)
    assert resp_missing_read["result"]["isError"] == true

    # 7. Update non-existent section
    req_missing_sec = %{
      "jsonrpc" => "2.0",
      "id" => 205,
      "method" => "tools/call",
      "params" => %{
        "name" => "choreo_update_design_section",
        "arguments" => %{
          "path" => full_nb,
          "section_name" => "Non Existent Section",
          "content" => "something"
        }
      }
    }

    resp_missing_sec = send_request(req_missing_sec)
    assert resp_missing_sec["result"]["isError"] == true

    assert hd(resp_missing_sec["result"]["content"])["text"] =~
             "Section 'Non Existent Section' not found"
  end

  test "MCP.start/0 processes stdio input, notifications, errors, and exits on EOF" do
    input = """
    {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
    {"jsonrpc": "2.0", "method": "notifications/initialized"}
    not valid json
    {"jsonrpc": "2.0", "id": 99, "invalid": json}
    """

    {:ok, io} = StringIO.open(input)
    original_gl = Process.group_leader()
    Process.group_leader(self(), io)

    try do
      assert MCP.start() == :ok
    after
      Process.group_leader(self(), original_gl)
    end

    {_, output} = StringIO.contents(io)
    assert output =~ "choreo_initialize_design_notebook"
    assert output =~ "Parse error"
  end

  test "Mix.Tasks.Choreo.Mcp runs and starts MCP server" do
    {:ok, io} = StringIO.open("")
    original_gl = Process.group_leader()
    Process.group_leader(self(), io)

    try do
      assert Mix.Tasks.Choreo.Mcp.run([]) == :ok
    after
      Process.group_leader(self(), original_gl)
    end
  end

  defp send_request(req) do
    # Simulates JSON-RPC handling with full serialization boundary
    req
    |> Jason.encode!()
    |> Jason.decode!()
    |> MCP.handle_request()
    |> Jason.encode!()
    |> Jason.decode!()
  end
end
