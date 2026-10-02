defmodule OpAMPServerWeb.Graph do
  @moduledoc """
  A directed graph for the UI: nodes with a type and data, and edges between them.

  Builders (for example `OpAMPServerWeb.Graph.Fleet`) make a graph from domain data,
  `OpAMPServerWeb.Graph.Layout` gives each node a position, and
  `OpAMPServerWeb.GraphComponents.graph/1` renders it.
  """

  defmodule Node do
    @moduledoc "A graph node. `x`, `y` and `rank` are set by the layout."
    @enforce_keys [:id, :type]
    defstruct [:id, :type, :data, width: 224, height: 72, x: 0, y: 0, rank: 0]
  end

  defmodule Edge do
    @moduledoc "A directed edge. `path` is an SVG path, set by the layout."
    @enforce_keys [:id, :from, :to]
    defstruct [:id, :from, :to, :path]
  end

  defstruct nodes: [], edges: [], width: 0, height: 0

  @type t :: %__MODULE__{nodes: [Node.t()], edges: [Edge.t()]}

  def new, do: %__MODULE__{}

  @doc """
  Adds a node. Options: `:data`, `:width`, `:height`. Adding an id twice keeps the first node.
  """
  def add_node(%__MODULE__{} = graph, id, type, opts \\ []) do
    if node(graph, id) do
      graph
    else
      node = struct!(Node, Keyword.merge([id: id, type: type], opts))
      %{graph | nodes: graph.nodes ++ [node]}
    end
  end

  @doc """
  Adds an edge from `from` to `to`. Adding the same edge twice keeps one.
  """
  def add_edge(%__MODULE__{} = graph, from, to) do
    id = "#{from}->#{to}"

    if Enum.any?(graph.edges, &(&1.id == id)),
      do: graph,
      else: %{graph | edges: graph.edges ++ [%Edge{id: id, from: from, to: to}]}
  end

  def node(%__MODULE__{nodes: nodes}, id), do: Enum.find(nodes, &(&1.id == id))
end
