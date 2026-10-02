defmodule OpAMPServerWeb.AgentLive.IndexTest do
  use OpAMPServerWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpAMPServer.AgentsFixtures

  alias OpAMPServer.Agents

  defp row(agent), do: "#agent-#{agent.id}"

  defp named(name, attrs \\ %{}) do
    agent_fixture(
      Map.merge(
        %{
          description: %Opamp.Proto.AgentDescription{
            identifying_attributes: [
              %Opamp.Proto.KeyValue{
                key: "service.name",
                value: %Opamp.Proto.AnyValue{value: {:string_value, name}}
              }
            ],
            non_identifying_attributes: [
              %Opamp.Proto.KeyValue{
                key: "host.name",
                value: %Opamp.Proto.AnyValue{value: {:string_value, "#{name}-host"}}
              }
            ]
          }
        },
        attrs
      )
    )
  end

  describe "listing" do
    test "shows each agent with its status, host, version, configs and remote config", %{
      conn: conn
    } do
      agent =
        agent_fixture(%{
          effective_config: effective_config_fixture(%{"default/a" => "a", "default/b" => "b"}),
          component_health: health_fixture(%{})
        })

      {:ok, view, html} = live(conn, ~p"/agents")

      assert html =~ "Agents"
      cells = view |> element(row(agent)) |> render()
      assert cells =~ "test-service"
      assert cells =~ agent.id
      assert cells =~ "Healthy"
      assert cells =~ "test-host"
      assert cells =~ ~r/>\s*2\s*</
      assert cells =~ "No remote config"
      assert cells =~ "just now"
    end

    test "says how many agents are connected", %{conn: conn} do
      for _ <- 1..3, do: agent_fixture()
      {:ok, _view, html} = live(conn, ~p"/agents")

      assert html =~ "3 connected."
    end

    test "sorts the agents by name", %{conn: conn} do
      zeta = named("zeta")
      alpha = named("alpha")
      {:ok, _view, html} = live(conn, ~p"/agents")

      assert :binary.match(html, "agent-#{alpha.id}") < :binary.match(html, "agent-#{zeta.id}")
    end

    test "shows an empty state without agents", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/agents")

      assert html =~ "No agents are connected"
      refute has_element?(view, "#agents")
    end

    test "shows an agent that has not reported health, config or a description", %{conn: conn} do
      {:ok, agent} = Agents.create_agent(%{id: Ecto.UUID.generate()})
      {:ok, view, _html} = live(conn, ~p"/agents")

      cells = view |> element(row(agent)) |> render()
      assert cells =~ "agent " <> String.slice(agent.id, 0, 8)
      assert cells =~ "Unknown"
      assert cells =~ ~r/>\s*0\s*</
    end

    test "shows a host.name that is not a string", %{conn: conn} do
      agent =
        agent_fixture(%{
          description: %Opamp.Proto.AgentDescription{
            non_identifying_attributes: [
              %Opamp.Proto.KeyValue{
                key: "host.name",
                value: %Opamp.Proto.AnyValue{value: {:int_value, 7}}
              }
            ]
          }
        })

      {:ok, view, _html} = live(conn, ~p"/agents")

      assert view |> element(row(agent)) |> render() =~ ~r/>\s*7\s*</
    end
  end

  describe "filter" do
    setup do
      %{alpha: named("alpha"), beta: named("beta")}
    end

    test "matches the name, the host and the instance uid", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/agents")

      for query <- ["alph", "ALPHA-HOST", String.slice(ctx.alpha.id, 0, 8)] do
        view |> form("#agent-filter", query: query) |> render_change()
        assert has_element?(view, row(ctx.alpha)), "#{query} should match alpha"
        refute has_element?(view, row(ctx.beta)), "#{query} should not match beta"
      end
    end

    test "shows an empty state when nothing matches", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/agents")

      html = view |> form("#agent-filter", query: "nope") |> render_change()

      assert html =~ "No agents match the filter"
    end

    test "an empty filter shows every agent", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/agents")

      view |> form("#agent-filter", query: "alpha") |> render_change()
      view |> form("#agent-filter", query: "") |> render_change()

      assert has_element?(view, row(ctx.alpha))
      assert has_element?(view, row(ctx.beta))
    end
  end

  describe "navigation" do
    test "the agent name opens the agent page", %{conn: conn} do
      agent = named("alpha")
      {:ok, view, _html} = live(conn, ~p"/agents")

      {:ok, _show, html} =
        view
        |> element("#{row(agent)} a", "alpha")
        |> render_click()
        |> follow_redirect(conn, ~p"/agents/#{agent.id}")

      assert html =~ agent.id
    end

    test "the sidebar marks Agents as the current page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/agents")

      assert has_element?(view, "nav a[aria-current=page]", "Agents")
    end
  end

  describe "live updates" do
    test "adds an agent when it connects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/agents")

      agent = agent_fixture()

      assert has_element?(view, row(agent))
    end

    test "updates an agent when it reports", %{conn: conn} do
      agent = agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/agents")

      {:ok, _} =
        Agents.update_agent(agent, %{
          effective_config: effective_config_fixture(%{"default/new" => "n"})
        })

      assert view |> element(row(agent)) |> render() =~ ~r/>\s*1\s*</
    end

    test "removes an agent when it disconnects", %{conn: conn} do
      agent = agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/agents")

      {:ok, _} = Agents.delete_agent(agent)

      refute has_element?(view, row(agent))
    end

    test "keeps rendering on each tick", %{conn: conn} do
      agent = agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/agents")

      send(view.pid, :tick)

      assert has_element?(view, row(agent))
    end
  end

  describe "delete" do
    test "removes the agent from the table and the database", %{conn: conn} do
      agent = agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/agents")

      view |> element("#{row(agent)} button[aria-label^=Delete]") |> render_click()

      refute has_element?(view, row(agent))
      assert Agents.get_agent(agent.id) == nil
    end

    test "does not crash when the agent is already gone", %{conn: conn} do
      agent = agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/agents")

      # For example, the agent disconnected after the page rendered its row.
      OpAMPServer.Repo.delete!(agent)
      render_click(view, "delete", %{"id" => agent.id})

      refute has_element?(view, row(agent))
    end
  end

  describe "removed pages" do
    test "the old pages do not exist", %{conn: conn} do
      agent = agent_fixture()

      for path <- ["/#{agent.id}", "/#{agent.id}/edit", "/#{agent.id}/show/edit", "/new"] do
        assert get(conn, path).status == 404, "#{path} should not exist"
      end
    end
  end
end
