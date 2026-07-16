defmodule Mix.Tasks.Choreo.TestLivebooks do
  use Mix.Task

  alias Choreo.Livebook

  @shortdoc "Runs and evaluates all Elixir blocks inside the Livebooks"
  @moduledoc """
  Finds and runs all Elixir code blocks inside the `.livemd` files under the `livebooks/` directory.
  Ensures that the notebooks execute successfully without any runtime compilation or execution errors.

  Notebooks that declare external dependencies beyond `choreo`, `kino`, and `kino_vizjs`
  are skipped, because those dependencies are fetched by `Mix.install/1` when the notebook
  runs inside Livebook and are not available in the project's test environment.

  Run this task via:
      mix choreo.test_livebooks
  """

  # Dependencies that are either already loaded in the project or mocked headlessly.
  @supported_deps MapSet.new([:choreo, :kino, :kino_vizjs])

  # Notebooks that cannot be validated headlessly because they depend on an
  # external project feature rather than a Hex package.
  @skipped_livebooks %{
    "livebooks/integrations/ecto_schema_erd.livemd" =>
      "requires a target project with Ecto schemas"
  }

  @impl Mix.Task
  def run(_args) do
    # Start the application dependencies
    Mix.Task.run("app.start")

    # Find all livebooks
    livebooks =
      Path.wildcard("livebooks/**/*.livemd")
      |> Enum.sort()

    Mix.shell().info("Found #{length(livebooks)} Livebooks to evaluate...\n")

    results =
      Enum.map(livebooks, fn path ->
        IO.write("Testing #{path}... ")

        case run_livebook(path) do
          :ok ->
            IO.write("\e[32m[OK]\e[0m\n")
            {:ok, path}

          :skipped ->
            IO.write("\e[33m[SKIPPED]\e[0m\n")
            {:skipped, path}

          {:error, exception, stacktrace} ->
            IO.write("\e[31m[FAIL]\e[0m\n")
            Mix.shell().info("\n\e[31mError in #{path}:\e[0m")
            Mix.shell().info(Exception.format(:error, exception, stacktrace))

            Mix.shell().info(
              "--------------------------------------------------------------------------------"
            )

            {:error, path, exception}
        end
      end)

    failures = Enum.filter(results, &match?({:error, _, _}, &1))

    if Enum.empty?(failures) do
      Mix.shell().info("\n\e[32mAll Livebooks executed successfully!\e[0m")
      :ok
    else
      Mix.shell().info("\n\e[31m#{length(failures)} Livebook(s) failed validation.\e[0m")
      System.at_exit(fn _ -> System.halt(1) end)
      :error
    end
  end

  defp run_livebook(path) do
    content = File.read!(path)

    case Map.fetch(@skipped_livebooks, path) do
      {:ok, reason} ->
        Mix.shell().info("\n  skipping: #{reason}")
        :skipped

      :error ->
        case external_dependencies(content) do
          [] ->
            content
            |> Livebook.extract_elixir_blocks()
            |> Livebook.evaluate_blocks()

          deps ->
            Mix.shell().info("\n  skipping: requires #{Enum.join(deps, ", ")}")
            :skipped
        end
    end
  end

  # Extracts dependency names declared in the notebook's Mix.install/1 call.
  # Returns a list of external dependency atoms not supported headlessly.
  defp external_dependencies(content) do
    blocks = Livebook.extract_elixir_blocks(content)

    blocks
    |> Enum.flat_map(&extract_mix_install_deps/1)
    |> Enum.reject(&MapSet.member?(@supported_deps, &1))
    |> Enum.uniq()
  end

  defp extract_mix_install_deps(code) do
    # Match Mix.install([...]) or Mix.install([...], opts) across multiple lines.
    case Regex.scan(~r/Mix\.install\(((?:[^()]|\([^()]*\))*)\)/s, code) do
      [] ->
        []

      matches ->
        matches
        |> Enum.flat_map(fn [_, inner] ->
          # The first argument should be the dependency list.
          case Regex.run(~r/^\s*\[(.*?)\]/s, inner, capture: :all_but_first) do
            [list_content] -> parse_dep_names(list_content)
            _ -> []
          end
        end)
    end
  end

  defp parse_dep_names(list_content) do
    list_content
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.flat_map(fn item ->
      case Regex.run(~r/^\{:(\w+)/, item) do
        [_, name] -> [String.to_atom(name)]
        _ -> []
      end
    end)
  end
end
