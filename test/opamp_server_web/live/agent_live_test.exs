defmodule OpAMPServerWeb.AgentLiveTest do
  use OpAMPServerWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpAMPServer.AgentsFixtures

  defp create_agent(_) do
    agent = agent_fixture()
    %{agent: agent}
  end

  describe "Index" do
    setup [:create_agent]

    test "lists all agent", %{conn: conn, agent: agent} do
      {:ok, _index_live, html} = live(conn, ~p"/")

      assert html =~ "Listing Agent"
      assert html =~ agent.id
    end

    test "deletes agent in listing", %{conn: conn, agent: agent} do
      {:ok, index_live, _html} = live(conn, ~p"/")

      assert index_live |> element("#agent_collection-#{agent.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#agent_collection-#{agent.id}")
    end
  end

  describe "Show" do
    setup [:create_agent]

    test "displays agent", %{conn: conn, agent: agent} do
      {:ok, _show_live, html} = live(conn, ~p"/#{agent}")

      assert html =~ "Showing Agent"
      assert html =~ agent.id
    end
  end
end
