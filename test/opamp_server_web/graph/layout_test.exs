defmodule OpAMPServerWeb.Graph.LayoutTest do
  use ExUnit.Case, async: true

  alias OpAMPServerWeb.Graph
  alias OpAMPServerWeb.Graph.Layout

  defp graph(nodes, edges) do
    graph = Enum.reduce(nodes, Graph.new(), &Graph.add_node(&2, &1, :box))
    Enum.reduce(edges, graph, fn {from, to}, g -> Graph.add_edge(g, from, to) end)
  end

  defp rank(graph, id), do: Graph.node(graph, id).rank
  defp y(graph, id), do: Graph.node(graph, id).y

  defp overlap?(a, b) do
    a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
  end

  test "an empty graph has no size" do
    assert %Graph{width: 0, height: 0} = Layout.layered(Graph.new())
  end

  test "each node goes one rank after its furthest predecessor" do
    laid_out =
      graph(~w(a b c d), [{"a", "b"}, {"b", "c"}, {"a", "c"}, {"c", "d"}]) |> Layout.layered()

    assert Enum.map(~w(a b c d), &rank(laid_out, &1)) == [0, 1, 2, 3]
  end

  test "nodes in one rank share a column, and later ranks are further right" do
    laid_out = graph(~w(root x y), [{"root", "x"}, {"root", "y"}]) |> Layout.layered()

    assert Graph.node(laid_out, "x").x == Graph.node(laid_out, "y").x
    assert Graph.node(laid_out, "x").x > Graph.node(laid_out, "root").x
  end

  test "no two nodes overlap" do
    edges = for i <- 1..6, j <- 1..3, do: {"agent-#{i}", "collector-#{i}-#{j}"}
    nodes = (["server"] ++ for({a, c} <- edges, do: [a, c])) |> List.flatten() |> Enum.uniq()
    edges = edges ++ for i <- 1..6, do: {"server", "agent-#{i}"}
    laid_out = graph(nodes, edges) |> Layout.layered()

    for a <- laid_out.nodes, b <- laid_out.nodes, a.id < b.id do
      refute overlap?(a, b), "#{a.id} overlaps #{b.id}"
    end
  end

  test "the graph size contains every node" do
    laid_out = graph(~w(a b c), [{"a", "b"}, {"a", "c"}]) |> Layout.layered(padding: 10)

    for node <- laid_out.nodes do
      assert node.x >= 10 and node.x + node.width <= laid_out.width - 10
      assert node.y >= 10 and node.y + node.height <= laid_out.height - 10
    end
  end

  test "barycenter ordering untangles crossed edges" do
    # Added in an order that crosses: a->y and b->x.
    laid_out = graph(~w(a b x y), [{"a", "y"}, {"b", "x"}]) |> Layout.layered()

    assert y(laid_out, "a") < y(laid_out, "b")
    assert y(laid_out, "y") < y(laid_out, "x")
  end

  test "align_sinks puts nodes without outgoing edges in the last column" do
    edges = [{"r", "p1"}, {"p1", "p2"}, {"p2", "e1"}, {"r", "e2"}]
    laid_out = graph(~w(r p1 p2 e1 e2), edges)

    assert rank(Layout.layered(laid_out), "e2") == 1
    assert rank(Layout.layered(laid_out, align_sinks: true), "e2") == 3
  end

  test "a cycle does not crash the layout" do
    laid_out = graph(~w(a b), [{"a", "b"}, {"b", "a"}]) |> Layout.layered()
    assert length(laid_out.nodes) == 2
  end

  test "each edge goes from the right side of its source to the left side of its target" do
    laid_out = graph(~w(a b), [{"a", "b"}]) |> Layout.layered()
    a = Graph.node(laid_out, "a")
    b = Graph.node(laid_out, "b")
    [edge] = laid_out.edges

    [x1, y1] = Regex.run(~r/^M (\S+) (\S+)/, edge.path, capture: :all_but_first)
    [x2, y2] = Regex.run(~r/, (\S+) (\S+)$/, edge.path, capture: :all_but_first)
    assert String.to_float(x1) == a.x + a.width
    assert String.to_float(y1) == a.y + a.height / 2
    assert String.to_float(x2) == b.x
    assert String.to_float(y2) == b.y + b.height / 2
  end

  test "an edge to an unknown node is dropped" do
    laid_out =
      Graph.new() |> Graph.add_node("a", :box) |> Graph.add_edge("a", "gone") |> Layout.layered()

    assert laid_out.edges == []
  end

  test "adding a node or an edge twice keeps one" do
    graph = graph(~w(a a b), [{"a", "b"}, {"a", "b"}])
    assert length(graph.nodes) == 2
    assert length(graph.edges) == 1
  end
end
