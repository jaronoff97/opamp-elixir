defmodule OpAMPServerWeb.AgentLive.IndexTest do
  use OpAMPServerWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpAMPServer.AgentsFixtures

  alias OpAMPServer.Agents

  defp row(agent), do: "#agent_collection-#{agent.id}"

  describe "listing" do
    test "shows each agent with its host, instance, heartbeat and collector count", %{conn: conn} do
      agent =
        agent_fixture(%{
          effective_config: effective_config_fixture(%{"default/a" => "a", "default/b" => "b"}),
          component_health: health_fixture(%{}, ~U[2026-01-02 15:04:05Z])
        })

      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Listing Agent"
      cells = view |> element(row(agent)) |> render()
      assert cells =~ "test-host"
      assert cells =~ agent.id
      assert cells =~ "03:04:05 PM"
      assert cells =~ ~r/>\s*2\s*</
    end

    test "shows every agent", %{conn: conn} do
      agents = for _ <- 1..3, do: agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/")

      for agent <- agents, do: assert(has_element?(view, row(agent)))
    end

    test "shows an empty table without agents", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#agent tr")
    end

    test "shows an agent that has not reported health, config or a description", %{conn: conn} do
      {:ok, agent} = Agents.create_agent(%{id: Ecto.UUID.generate()})

      {:ok, view, _html} = live(conn, ~p"/")

      cells = view |> element(row(agent)) |> render()
      assert cells =~ agent.id
      assert cells =~ ~r/>\s*0\s*</
    end

    test "shows an empty host name when host.name is not a string", %{conn: conn} do
      agent =
        agent_fixture(%{
          description: %Opamp.Proto.AgentDescription{
            identifying_attributes: [
              %Opamp.Proto.KeyValue{
                key: "host.name",
                value: %Opamp.Proto.AnyValue{value: {:int_value, 7}}
              }
            ]
          }
        })

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, row(agent))
    end
  end

  describe "navigation" do
    test "the Show link opens the agent page", %{conn: conn} do
      agent = agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/")

      {:ok, _show, html} =
        view
        |> element("#{row(agent)} a", "Show")
        |> render_click()
        |> follow_redirect(conn, ~p"/#{agent}")

      assert html =~ "Agent #{agent.id}"
    end
  end

  describe "removed pages" do
    # Agents get their rows from OpAMP connections, so the server has no forms to edit them.
    test "the index has no Edit link", %{conn: conn} do
      agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "a", "Edit")
    end

    test "the edit pages do not exist", %{conn: conn} do
      agent = agent_fixture()

      assert get(conn, "/#{agent.id}/edit").status == 404
      assert get(conn, "/#{agent.id}/show/edit").status == 404
    end

    test "/new is not a page, so it goes back to the index", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/new")
    end
  end

  describe "live updates" do
    test "adds an agent when it connects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      agent = agent_fixture()

      assert has_element?(view, row(agent))
    end

    test "updates an agent when it reports", %{conn: conn} do
      agent = agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/")

      {:ok, _} =
        Agents.update_agent(agent, %{
          effective_config: effective_config_fixture(%{"default/new" => "n"})
        })

      assert view |> element(row(agent)) |> render() =~ ~r/>\s*1\s*</
    end

    test "removes an agent when it disconnects", %{conn: conn} do
      agent = agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/")

      {:ok, _} = Agents.delete_agent(agent)

      refute has_element?(view, row(agent))
    end
  end

  describe "delete" do
    test "removes the agent from the table and the database", %{conn: conn} do
      agent = agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#{row(agent)} a", "Delete") |> render_click()

      refute has_element?(view, row(agent))
      assert Agents.get_agent(agent.id) == nil
    end

    test "does not crash when the agent is already gone", %{conn: conn} do
      agent = agent_fixture()
      {:ok, view, _html} = live(conn, ~p"/")

      # For example, the agent disconnected after the page rendered its row.
      OpAMPServer.Repo.delete!(agent)
      render_click(view, "delete", %{"id" => agent.id})

      refute has_element?(view, row(agent))
    end
  end
end
