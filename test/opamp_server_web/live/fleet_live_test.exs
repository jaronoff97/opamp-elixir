defmodule OpAMPServerWeb.FleetLiveTest do
  use OpAMPServerWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpAMPServer.AgentsFixtures

  alias OpAMPServer.Agents

  defp node_el(id), do: "[id='fleet-node-#{id}']"

  defp bridge_agent(attrs \\ %{}) do
    agent_fixture(
      Map.merge(
        %{
          effective_config: effective_config_fixture(%{"default/a" => collector_body("a")}),
          component_health: health_fixture(%{"default/a" => ["a-pod-1"]})
        },
        attrs
      )
    )
  end

  defp stat(html, label) do
    [_, value] = Regex.run(~r/(\d+)<\/div>\s*<div[^>]*>#{label}</, html)
    String.to_integer(value)
  end

  test "shows the server, each agent and each collector as nodes", %{conn: conn} do
    agent = bridge_agent()
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, node_el("server"), "1 agent")
    assert has_element?(view, node_el("agent:#{agent.id}"), "test-service")
    assert has_element?(view, node_el("agent:#{agent.id}"), "bridge")
    assert has_element?(view, node_el("collector:#{agent.id}:default/a"), "1/1 pods ready")
    assert has_element?(view, "path[id='fleet-edge-server->agent:#{agent.id}']")
    assert has_element?(view, "nav a[aria-current=page]", "Fleet")
  end

  test "sums up the fleet", %{conn: conn} do
    bridge_agent()

    agent_fixture(%{
      component_health: %Opamp.Proto.ComponentHealth{healthy: false, last_error: "boom"}
    })

    {:ok, _view, html} = live(conn, ~p"/")

    assert stat(html, "Connected agents") == 2
    assert stat(html, "Healthy") == 1
    assert stat(html, "Collectors") == 1
    assert stat(html, "Need attention") == 1
  end

  test "explains how to connect when no agent is connected", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "No agents are connected."
    assert html =~ "/v1/opamp"
    assert has_element?(view, node_el("server"), "0 agents")
  end

  describe "details" do
    test "a click on an agent shows it, and a second click hides it", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#{node_el("agent:#{agent.id}")} button") |> render_click()
      details = view |> element("#fleet-details") |> render()
      assert details =~ "test-service"
      assert details =~ agent.id
      assert has_element?(view, "#fleet-details a[href='/agents/#{agent.id}']", "Open agent")
      assert has_element?(view, "#{node_el("agent:#{agent.id}")} button[aria-pressed=true]")

      view |> element("#{node_el("agent:#{agent.id}")} button") |> render_click()
      refute has_element?(view, "#fleet-details")
    end

    test "a collector links to its config and its pipeline", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#{node_el("collector:#{agent.id}:default/a")} button") |> render_click()

      assert has_element?(
               view,
               "#fleet-details a[href='/agents/#{agent.id}/config?object=default%2Fa']"
             )

      assert has_element?(
               view,
               "#fleet-details a[href='/agents/#{agent.id}/pipeline?object=default%2Fa']"
             )
    end

    test "the server links to the settings, and the close button hides the details", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#{node_el("server")} button") |> render_click()
      assert has_element?(view, "#fleet-details a[href='/settings']")

      view |> element("#fleet-details button[aria-label=Close]") |> render_click()
      refute has_element?(view, "#fleet-details")
    end
  end

  describe "live updates" do
    test "adds an agent when it connects, and updates the server node", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      agent = bridge_agent()

      assert has_element?(view, node_el("agent:#{agent.id}"))
      assert has_element?(view, node_el("server"), "1 agent")
    end

    test "shows a new collector when an agent reports one", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/")

      {:ok, _} =
        Agents.update_agent(agent, %{
          effective_config: effective_config_fixture(%{"default/b" => collector_body("b")})
        })

      assert has_element?(view, node_el("collector:#{agent.id}:default/b"))
      refute has_element?(view, node_el("collector:#{agent.id}:default/a"))
    end

    test "removes a disconnected agent, and closes its details", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#{node_el("agent:#{agent.id}")} button") |> render_click()

      {:ok, _} = Agents.delete_agent(agent)

      refute has_element?(view, node_el("agent:#{agent.id}"))
      refute has_element?(view, "#fleet-details")
    end

    test "keeps rendering on each tick", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/")

      send(view.pid, :tick)

      assert has_element?(view, node_el("agent:#{agent.id}"), "seen just now")
    end
  end
end
