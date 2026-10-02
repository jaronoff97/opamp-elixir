defmodule OpAMPServerWeb.Graph.Layout do
  @moduledoc """
  A layered layout for directed graphs, from left to right.

    1. Rank: each node goes one rank after its furthest predecessor (longest path).
    2. Order: a few barycenter passes order each rank to reduce edge crossings.
    3. Place: each rank is a column, centered on the tallest column.
    4. Route: each edge is a bezier curve from the right side of its source to the
       left side of its target.

  ponytail: no dummy nodes for edges that skip ranks, so such edges can cross nodes.
  Builders keep graphs layered (fleet, pipelines). Add dummy nodes if a graph needs it.
  """

  alias OpAMPServerWeb.Graph

  @defaults [rank_gap: 96, node_gap: 24, padding: 24, align_sinks: false, passes: 4]

  @doc """
  Sets `x`, `y` and `rank` on each node, `path` on each edge, and the graph size.

  Options:

    * `:rank_gap` - the space between columns (default 96)
    * `:node_gap` - the space between the nodes of a column (default 24)
    * `:padding` - the space around the graph (default 24)
    * `:align_sinks` - put nodes without outgoing edges in the last column (default false)
  """
  def layered(graph, opts \\ [])
  def layered(%Graph{nodes: []} = graph, _opts), do: %{graph | width: 0, height: 0}

  def layered(%Graph{} = graph, opts) do
    opts = Keyword.merge(@defaults, opts)
    ids = MapSet.new(graph.nodes, & &1.id)
    graph = %{graph | edges: Enum.filter(graph.edges, &(&1.from in ids and &1.to in ids))}
    ranks = graph |> ranks() |> maybe_align_sinks(graph, opts[:align_sinks])
    columns = graph |> columns(ranks) |> order(graph, opts[:passes])
    {nodes, width, height} = place(graph, columns, opts)
    by_id = Map.new(nodes, &{&1.id, &1})

    edges = for edge <- graph.edges, do: %{edge | path: path(by_id[edge.from], by_id[edge.to])}

    %{graph | nodes: nodes, edges: edges, width: width, height: height}
  end

  # Longest path from a source, in topological order (Kahn). A node in a cycle never gets
  # all its predecessors ranked, so it falls back to rank 0.
  defp ranks(graph) do
    preds = Enum.group_by(graph.edges, & &1.to, & &1.from)
    succs = Enum.group_by(graph.edges, & &1.from, & &1.to)
    indegree = Map.new(graph.nodes, &{&1.id, length(Map.get(preds, &1.id, []))})
    sources = for node <- graph.nodes, indegree[node.id] == 0, do: node.id
    ranks = walk(sources, succs, indegree, Map.new(sources, &{&1, 0}))

    Map.new(graph.nodes, &{&1.id, Map.get(ranks, &1.id, 0)})
  end

  defp walk([], _succs, _indegree, ranks), do: ranks

  defp walk([id | rest], succs, indegree, ranks) do
    {ready, indegree, ranks} =
      Enum.reduce(Map.get(succs, id, []), {[], indegree, ranks}, fn next, {ready, indeg, ranks} ->
        ranks = Map.update(ranks, next, ranks[id] + 1, &max(&1, ranks[id] + 1))
        indeg = Map.update!(indeg, next, &(&1 - 1))
        {if(indeg[next] == 0, do: ready ++ [next], else: ready), indeg, ranks}
      end)

    walk(rest ++ ready, succs, indegree, ranks)
  end

  defp maybe_align_sinks(ranks, _graph, false), do: ranks

  defp maybe_align_sinks(ranks, graph, true) do
    last = ranks |> Map.values() |> Enum.max(fn -> 0 end)
    sources = MapSet.new(graph.edges, & &1.from)
    Map.new(ranks, fn {id, rank} -> {id, if(id in sources, do: rank, else: last)} end)
  end

  # Columns of node ids, in the order that the builder added the nodes.
  defp columns(graph, ranks) do
    max_rank = ranks |> Map.values() |> Enum.max()
    by_rank = Enum.group_by(graph.nodes, &ranks[&1.id], & &1.id)
    for rank <- 0..max_rank, do: Map.get(by_rank, rank, [])
  end

  # Alternate sweeps: order each column by the mean position of its neighbors in the column
  # before it (down) or after it (up). Nodes without such neighbors keep their position.
  defp order(columns, graph, passes) do
    preds = Enum.group_by(graph.edges, & &1.to, & &1.from)
    succs = Enum.group_by(graph.edges, & &1.from, & &1.to)

    Enum.reduce(1..passes, columns, fn pass, columns ->
      if rem(pass, 2) == 1,
        do: sweep(columns, preds),
        else: columns |> Enum.reverse() |> sweep(succs) |> Enum.reverse()
    end)
  end

  defp sweep([first | rest], neighbors) do
    rest
    |> Enum.reduce([first], fn column, [previous | _] = done ->
      position = previous |> Enum.with_index() |> Map.new()

      sorted =
        column
        |> Enum.with_index()
        |> Enum.sort_by(fn {id, index} ->
          case for n <- Map.get(neighbors, id, []), Map.has_key?(position, n), do: position[n] do
            [] -> {index, index}
            positions -> {Enum.sum(positions) / length(positions), index}
          end
        end)
        |> Enum.map(&elem(&1, 0))

      [sorted | done]
    end)
    |> Enum.reverse()
  end

  defp place(graph, columns, opts) do
    by_id = Map.new(graph.nodes, &{&1.id, &1})
    gap = opts[:node_gap]
    pad = opts[:padding]

    heights =
      for column <- columns do
        column
        |> Enum.map(&by_id[&1].height)
        |> Enum.sum()
        |> Kernel.+(gap * max(length(column) - 1, 0))
      end

    tallest = Enum.max(heights)

    {nodes, x} =
      columns
      |> Enum.zip(heights)
      |> Enum.with_index()
      |> Enum.reduce({[], pad}, fn {{column, height}, rank}, {nodes, x} ->
        {placed, _y} =
          Enum.map_reduce(column, pad + (tallest - height) / 2, fn id, y ->
            node = by_id[id]
            {%{node | x: x, y: y, rank: rank}, y + node.height + gap}
          end)

        width = column |> Enum.map(&by_id[&1].width) |> Enum.max(fn -> 0 end)
        {nodes ++ placed, x + width + opts[:rank_gap]}
      end)

    {nodes, x - opts[:rank_gap] + pad, tallest + 2 * pad}
  end

  defp path(from, to) do
    {x1, y1} = {from.x + from.width, from.y + from.height / 2}
    {x2, y2} = {to.x, to.y + to.height / 2}
    dx = max((x2 - x1) / 2, 24)
    "M #{n(x1)} #{n(y1)} C #{n(x1 + dx)} #{n(y1)}, #{n(x2 - dx)} #{n(y2)}, #{n(x2)} #{n(y2)}"
  end

  defp n(value), do: :erlang.float_to_binary(value / 1, decimals: 1)
end
