defmodule OpAMPServerWeb.GraphComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import OpAMPServerWeb.GraphComponents

  alias OpAMPServerWeb.Graph
  alias OpAMPServerWeb.Graph.Layout

  defp graph do
    Graph.new()
    |> Graph.add_node("a", :box, data: "A")
    |> Graph.add_node("b", :box, data: "B")
    |> Graph.add_edge("a", "b")
    |> Layout.layered()
  end

  defp render_graph(assigns) do
    assigns = Map.merge(%{graph: graph(), selected: nil, on_select: nil}, assigns)

    rendered_to_string(~H"""
    <.graph id="g" graph={@graph} selected={@selected} on_select={@on_select}>
      <:node :let={node}>card {node.data}</:node>
      <:empty>nothing here</:empty>
    </.graph>
    """)
  end

  test "places each node where the layout put it, and draws each edge" do
    html = render_graph(%{})
    a = Graph.node(graph(), "a")
    [edge] = graph().edges

    assert html =~ ~s(id="g-node-a")
    assert html =~ "left: #{a.x}px; top: #{a.y}px; width: #{a.width}px; height: #{a.height}px"
    assert html =~ "card A"
    assert html =~ ~s(d="#{edge.path}")
    assert html =~ ~s(data-width="#{graph().width}")
    refute html =~ "nothing here"
  end

  test "without on_select, nodes are not buttons" do
    refute render_graph(%{}) =~ "aria-pressed"
  end

  test "with on_select, each node is a button that sends its id" do
    html = render_graph(%{on_select: "select", selected: "a"})

    assert html =~ ~s(phx-click="select")
    assert html =~ ~s(phx-value-id="a")
    assert html =~ ~s(aria-pressed="true")
    assert html =~ ~s(aria-pressed="false")
  end

  test "highlights the edges of the selected node" do
    assert render_graph(%{selected: "a"}) =~ ~r/id="g-edge-a-&gt;b"[^>]*stroke-primary/
    refute render_graph(%{selected: nil}) =~ "stroke-primary"
  end

  test "shows the empty slot without nodes" do
    assert render_graph(%{graph: Layout.layered(Graph.new())}) =~ "nothing here"
  end

  test "has zoom and fit controls" do
    html = render_graph(%{})

    for label <- ["Zoom in", "Zoom out", "Fit to view"], do: assert(html =~ label)
  end
end
