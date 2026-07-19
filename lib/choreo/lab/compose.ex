defmodule Choreo.Lab.Compose do
  @moduledoc """
  Pipe-friendly composition helpers for assembling Choreo models in Livebook.

  This module is ordinary Elixir, not a macro DSL. It is a thin convenience
  layer over the stable composition primitives in `Choreo`: clusters, embedding,
  normal graph connections, and semantic trace links.

  `Choreo` remains the primitive composition API. `Choreo.Lab.Compose` is the
  ergonomic exploration API for building larger composed models from smaller
  Choreo diagrams.

  Prefer alias-qualified usage for better editor autocomplete:

      alias Choreo.Lab.Compose

      Choreo.new()
      |> Compose.cluster("system", label: "System")
      |> Compose.embed(infra, into: "system", as: :infra)
      |> Compose.embed(auth_fsm, into: "system", as: :auth)
      |> Compose.trace(:infra_auth, :auth_unauthenticated, :executes)

  `connect/4` creates a normal visible relationship. `trace/4` creates a
  semantic cross-model relationship that `Choreo.Analysis.Tracing` and
  `Choreo.View.focus_trace/4` can follow.
  """

  @type system :: Choreo.t()
  @type node_id :: Yog.node_id()
  @type cluster_id :: String.t() | atom()

  @doc """
  Returns the composition helper vocabulary for Livebook discovery.

      iex> verbs = Choreo.Lab.Compose.verbs()
      iex> :embed in verbs.structure
      true
      iex> :trace in verbs.links
      true
      iex> :as in verbs.options
      true
  """
  @spec verbs() :: %{
          structure: [atom()],
          links: [atom()],
          options: [atom()]
        }
  def verbs do
    %{
      structure: [:cluster, :embed],
      links: [:connect, :trace],
      options: [:into, :as, :prefix, :label, :type]
    }
  end

  @doc """
  Adds a visual cluster/grouping boundary to a composed system.

      iex> system = Choreo.new() |> Choreo.Lab.Compose.cluster(:auth, label: "Auth")
      iex> Map.has_key?(system.clusters, "cluster_auth")
      true
  """
  @spec cluster(system(), cluster_id(), keyword()) :: system()
  def cluster(%Choreo{} = system, name, opts \\ []) do
    Choreo.add_cluster(system, name, opts)
  end

  @doc """
  Embeds a child diagram into a cluster of the parent system.

  Required options:

    * `:into` — target cluster name/id

  Prefix options:

    * `:as` — friendly alias converted to a prefix with a trailing underscore
    * `:prefix` — explicit prefix passed through to `Choreo.embed/4`

  `:prefix` wins over `:as` when both are supplied.

      iex> child = Choreo.new() |> Choreo.add_service(:api)
      iex> system =
      ...>   Choreo.new()
      ...>   |> Choreo.Lab.Compose.cluster(:system)
      ...>   |> Choreo.Lab.Compose.embed(child, into: :system, as: :child)
      iex> Map.has_key?(Choreo.nodes(system), :child_api)
      true
  """
  @spec embed(system(), struct(), keyword()) :: system()
  def embed(%Choreo{} = system, child, opts) when is_struct(child) and is_list(opts) do
    into = Keyword.fetch!(opts, :into)
    prefix = embed_prefix(opts)
    Choreo.embed(system, child, into, prefix: prefix)
  end

  @doc """
  Connects two nodes with a normal visible relationship.

  The third argument may be a label string, a keyword list, or omitted.

      iex> system =
      ...>   Choreo.new()
      ...>   |> Choreo.add_service(:api)
      ...>   |> Choreo.add_database(:db)
      ...>   |> Choreo.Lab.Compose.connect(:api, :db, "reads")
      iex> [{:api, :db, _weight, meta}] = Choreo.edges_with_meta(system)
      iex> meta.label
      "reads"
  """
  @spec connect(system(), node_id(), node_id(), String.t() | keyword()) :: system()
  def connect(%Choreo{} = system, from, to, label_or_opts \\ []) do
    Choreo.connect(system, from, to, normalize_label_or_opts(label_or_opts))
  end

  @doc """
  Adds a semantic trace relationship between two nodes.

  The fourth argument may be a trace type atom, a keyword list, or omitted.

      iex> system =
      ...>   Choreo.new()
      ...>   |> Choreo.add_service(:api)
      ...>   |> Choreo.add_service(:auth)
      ...>   |> Choreo.Lab.Compose.trace(:api, :auth, :executes)
      iex> [{:api, :auth, _weight, meta}] = Choreo.edges_with_meta(system)
      iex> {meta.edge_type, meta.type, meta.label}
      {:trace, :executes, "executes"}
  """
  @spec trace(system(), node_id(), node_id(), atom() | keyword()) :: system()
  def trace(%Choreo{} = system, from, to, type_or_opts \\ []) do
    Choreo.trace(system, from, to, normalize_type_or_opts(type_or_opts))
  end

  defp embed_prefix(opts) do
    cond do
      prefix = Keyword.get(opts, :prefix) ->
        to_string(prefix)

      as = Keyword.get(opts, :as) ->
        as
        |> to_string()
        |> String.trim_trailing("_")
        |> Kernel.<>("_")

      true ->
        "sub_"
    end
  end

  defp normalize_label_or_opts(label) when is_binary(label), do: [label: label]
  defp normalize_label_or_opts(opts) when is_list(opts), do: opts

  defp normalize_type_or_opts(type) when is_atom(type), do: [type: type]
  defp normalize_type_or_opts(opts) when is_list(opts), do: opts
end
