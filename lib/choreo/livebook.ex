defmodule Choreo.Livebook do
  @moduledoc """
  Shared helpers for parsing and headlessly evaluating Choreo Livebooks.

  Used by `Mix.Tasks.Choreo.TestLivebooks` and `Choreo.MCP` so that both
  tools validate notebooks with the same parser, mock suite, and evaluation
  semantics.
  """

  @doc """
  Extracts `elixir` code blocks from a Livebook markdown string.

  The parser is nested-fence aware: it matches the exact opening backtick
  sequence and only closes the block on the same sequence. This avoids
  truncating blocks that contain triple-backtick strings.
  """
  @spec extract_elixir_blocks(String.t()) :: [String.t()]
  def extract_elixir_blocks(content) do
    content
    |> String.split("\n")
    |> Enum.reduce({[], nil, []}, fn line, {blocks, current_block, current_lines} ->
      case current_block do
        nil ->
          case Regex.run(~r/^(`{3,})elixir\s*$/, line) do
            [_, ticks] -> {blocks, ticks, []}
            _ -> {blocks, nil, []}
          end

        ticks ->
          if String.trim(line) == ticks do
            block = Enum.reverse(current_lines) |> Enum.join("\n")
            {[block | blocks], nil, []}
          else
            {blocks, ticks, [line | current_lines]}
          end
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc """
  Evaluates the extracted Elixir blocks in a headless environment.

  * Strips `Mix.install([...])` calls (the host already has dependencies).
  * Redirects `Kino.*` calls to `Choreo.Livebook.KinoMock`.
  * Replaces visual renderers with `Kernel.inspect` so they return plain values.

  Returns `:ok` on success or `{:error, exception, stacktrace}` on failure.
  """
  @spec evaluate_blocks([String.t()]) :: :ok | {:error, struct(), Exception.stacktrace()}
  def evaluate_blocks(blocks) do
    code_to_eval =
      blocks
      |> Enum.map_join("\n", &strip_mix_install/1)
      |> String.replace("Choreo.Lab.Siren.new", "Kernel.inspect")
      |> String.replace("Choreo.Lab.Sketch.new", "Kernel.inspect")

    env =
      __ENV__
      |> Map.put(:aliases, [{Kino, Choreo.Livebook.KinoMock} | __ENV__.aliases])
      |> Map.put(:requires, [Choreo.Livebook.KinoMock | __ENV__.requires])

    Code.eval_string(code_to_eval, [], env)
    :ok
  rescue
    exception -> {:error, exception, __STACKTRACE__}
  end

  @doc """
  Parses markdown headers and their contents, skipping lines inside fenced
  code blocks so that commented Elixir code is not mistaken for a section.
  """
  @spec parse_sections(String.t()) :: [%{section: String.t(), content: String.t()}]
  def parse_sections(content) do
    lines = String.split(content, "\n")

    {sections, current_section, current_body, _fence} =
      Enum.reduce(lines, {[], nil, [], nil}, fn line,
                                                {acc_sections, current_name, acc_body,
                                                 fence_ticks} ->
        case parse_line(line, fence_ticks) do
          {:fence, ticks} ->
            {acc_sections, current_name, [line | acc_body], ticks}

          {:header, header} when fence_ticks == nil ->
            new_acc_sections =
              if current_name do
                [%{section: current_name, content: join_body(acc_body)} | acc_sections]
              else
                acc_sections
              end

            {new_acc_sections, header, [], fence_ticks}

          _ ->
            {acc_sections, current_name, [line | acc_body], fence_ticks}
        end
      end)

    final_sections =
      if current_section do
        [%{section: current_section, content: join_body(current_body)} | sections]
      else
        sections
      end

    Enum.reverse(final_sections)
  end

  defp parse_line(line, nil) do
    case Regex.run(~r/^(`{3,})\s*$/, line) do
      [_, ticks] ->
        {:fence, ticks}

      _ ->
        case Regex.run(~r/^(`{3,})\w+\s*$/, line) do
          [_, ticks] -> {:fence, ticks}
          _ -> if String.starts_with?(line, "#"), do: {:header, String.trim(line)}, else: :text
        end
    end
  end

  defp parse_line(line, ticks) do
    if String.trim(line) == ticks do
      {:fence, nil}
    else
      :text
    end
  end

  defp join_body(body), do: body |> Enum.reverse() |> Enum.join("\n")

  defp strip_mix_install(code) do
    # Mix.install may be written across multiple lines and may include
    # additional keyword arguments, e.g.:
    #   Mix.install(
    #     [...],
    #     consolidate_protocols: false
    #   )
    String.replace(code, ~r/Mix\.install\((?:[^()]|\([^()]*\))*\)/s, "")
  end
end
