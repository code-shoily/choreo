defprotocol Choreo.Viewable do
  @moduledoc """
  Protocol for graph lens transforms (focus, zoom, filter, collapse) on Choreo diagrams.

  Each diagram module that supports `Choreo.View` must implement this protocol
  to define:

    * How to rebuild the struct after graph mutation (pruning edge_meta,
      resolving root, etc.)
    * Which nodes are visible at each zoom level
    * How virtual edges (created by transitive filtering) are styled

  ## Implementing the protocol

      defimpl Choreo.Viewable, for: MyModule do
        def rebuild(diagram, new_graph) do
          # Prune edge_meta, resolve root, return new struct
        end

        def zoom_predicate(_diagram, 0), do: fn data -> data[:node_type] == :root end
        def zoom_predicate(_diagram, 1), do: fn data -> data[:node_type] in [:root, :topic] end
        def zoom_predicate(_diagram, _level), do: fn _data -> true end

        def virtual_edge_meta(_diagram), do: %{edge_type: :virtual}
      end
  """

  @fallback_to_any true

  @doc """
  Rebuild the diagram after a graph transformation.

  Responsible for pruning `edge_meta` to only include edges that still exist
  in `new_graph`, adding virtual edge metadata for any graph edges that lack
  it, and resolving any root/cluster references that may have been removed.
  """
  def rebuild(diagram, new_graph)

  @doc """
  Return a predicate for `Yog.filter_nodes/2` at the given zoom level.

  The predicate receives node data (not the id) and returns a boolean.
  Return `fn _data -> true end` for "show everything".
  """
  def zoom_predicate(diagram, level)

  @doc """
  Return metadata for virtual edges created during transitive filtering.

  Virtual edges connect remaining nodes that were previously linked through
  removed intermediate nodes.
  """
  def virtual_edge_meta(diagram)
end
