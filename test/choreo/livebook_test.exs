defmodule Choreo.LivebookTest do
  use ExUnit.Case, async: true

  alias Choreo.Livebook
  alias Choreo.Livebook.KinoMock

  describe "Choreo.Livebook" do
    test "extract_elixir_blocks/1 extracts elixir blocks with nested fences" do
      doc = """
      # Notebook Title

      Some text here.

      ```elixir
      x = 1
      y = 2
      ```

      Intermediary markdown.

      ````elixir
      nested = ~s\"\"\"
      ```elixir
      inner = :ok
      ```
      \"\"\"
      ````

      ```markdown
      not elixir
      ```
      """

      blocks = Livebook.extract_elixir_blocks(doc)
      assert length(blocks) == 2
      assert Enum.at(blocks, 0) =~ "x = 1"
      assert Enum.at(blocks, 1) =~ "inner = :ok"
    end

    test "evaluate_blocks/1 evaluates code blocks headlessly and handles errors" do
      blocks = [
        """
        Mix.install([{:choreo, path: "."}])
        a = 10
        b = 20
        """
      ]

      assert :ok = Livebook.evaluate_blocks(blocks)

      failing_blocks = [
        """
        raise "Intentional evaluation error"
        """
      ]

      assert {:error, %RuntimeError{message: "Intentional evaluation error"}, _stack} =
               Livebook.evaluate_blocks(failing_blocks)
    end

    test "parse_sections/1 extracts headers while ignoring headers inside code blocks" do
      doc = """
      # Section 1
      Content for section 1.

      ```elixir
      # This is a comment, not a header
      val = 42
      ```

      ## Section 2
      Content for section 2.
      """

      sections = Livebook.parse_sections(doc)
      assert length(sections) == 2
      assert Enum.at(sections, 0).section == "# Section 1"
      assert Enum.at(sections, 0).content =~ "Content for section 1."
      assert Enum.at(sections, 0).content =~ "# This is a comment, not a header"
      assert Enum.at(sections, 1).section == "## Section 2"
      assert Enum.at(sections, 1).content =~ "Content for section 2."
    end
  end

  describe "Choreo.Livebook.KinoMock" do
    test "Layout mocks return expected values" do
      assert KinoMock.Layout.tabs(A: 1, B: 2) == [A: 1, B: 2]
      assert KinoMock.Layout.grid([:item1, :item2]) == [:item1, :item2]
    end

    test "Markdown, HTML, Text, Mermaid, and VizJS mocks return raw content" do
      assert KinoMock.Markdown.new("# Title") == "# Title"
      assert KinoMock.HTML.new("<div>hello</div>") == "<div>hello</div>"
      assert KinoMock.Text.new("plain text") == "plain text"
      assert KinoMock.Mermaid.new("graph TD; A-->B") == "graph TD; A-->B"
      assert KinoMock.VizJS.render("digraph G { a -> b }") == "digraph G { a -> b }"
      assert KinoMock.DataTable.new([%{a: 1}]) == [%{a: 1}]

      assert KinoMock.JS.new(:module_name, %{data: 1}) == %{
               module: :module_name,
               data: %{data: 1}
             }
    end

    test "Input and Control mocks provide sensible defaults" do
      assert KinoMock.Input.text("Label", default: "default text") == {:input, "default text"}
      assert KinoMock.Input.password("Pass", default: "secret") == {:input, "secret"}
      assert KinoMock.Input.textarea("Desc", default: "multi\\nline") == {:input, "multi\\nline"}
      assert KinoMock.Input.number("Num", default: 42) == {:input, 42}
      assert KinoMock.Input.checkbox("Agree", default: true) == {:input, true}

      assert KinoMock.Input.select("Pick", [{"opt1", "Option 1"}, {"opt2", "Option 2"}]) ==
               {:input, "opt1"}

      assert KinoMock.Input.select("Pick", [{"opt1", "Option 1"}], default: "custom") ==
               {:input, "custom"}

      assert KinoMock.Input.read({:input, "read_val"}) == "read_val"
      assert KinoMock.Input.read("direct_val") == "direct_val"

      assert KinoMock.Control.button("Click Me") == {:control, "Click Me"}

      assert KinoMock.Control.select("Ctrl Pick", [{"c1", "Choice 1"}]) == {:control, "c1"}

      assert KinoMock.Control.select("Ctrl Pick", [{"c1", "Choice 1"}], default: "c2") ==
               {:control, "c2"}
    end

    test "Frame, Image, Download, Process, and top-level render" do
      assert KinoMock.Frame.new() == {:frame, nil}
      assert KinoMock.Frame.render({:frame, nil}, :content) == {{:frame, nil}, :content}
      assert KinoMock.Image.new("binary_data", "image/png") == "binary_data"

      download_fn = fn -> "data" end
      assert KinoMock.Download.new(download_fn) == download_fn
      assert KinoMock.Process.render(:proc_content) == :proc_content
      assert KinoMock.render(:top_level) == :top_level
    end
  end

  describe "Mix.Tasks.Choreo.TestLivebooks" do
    test "task module exists and defines the mix task" do
      assert Mix.Tasks.Choreo.TestLivebooks.__info__(:functions) |> Keyword.has_key?(:run)
    end

    test "runs the task successfully" do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

      ExUnit.CaptureIO.capture_io(fn ->
        assert Mix.Tasks.Choreo.TestLivebooks.run([]) == :ok
      end)
    end
  end
end
