defmodule OpAMPServerWeb.AgentLiveTest do
  use OpAMPServerWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpAMPServer.AgentsFixtures

  @create_attrs %{instance_id: "some instance_id", effective_config: %{}}
  @update_attrs %{instance_id: "some updated instance_id", effective_config: %{}}
  @invalid_attrs %{instance_id: nil, effective_config: nil}

  defp create_agent(_) do
    agent = agent_fixture()
    %{agent: agent}
  end

  describe "Index" do
    setup [:create_agent]

    test "lists all agent", %{conn: conn, agent: agent} do
      {:ok, _index_live, html} = live(conn, ~p"/agent")

      assert html =~ "Listing Agent"
      assert html =~ agent.instance_id
    end

    test "saves new agent", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/agent")

      assert index_live |> element("a", "New Agent") |> render_click() =~
               "New Agent"

      assert_patch(index_live, ~p"/agent/new")

      assert index_live
             |> form("#agent-form", agent: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#agent-form", agent: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/agent")

      html = render(index_live)
      assert html =~ "Agent created successfully"
      assert html =~ "some instance_id"
    end

    test "updates agent in listing", %{conn: conn, agent: agent} do
      {:ok, index_live, _html} = live(conn, ~p"/agent")

      assert index_live |> element("#agent-#{agent.id} a", "Edit") |> render_click() =~
               "Edit Agent"

      assert_patch(index_live, ~p"/agent/#{agent}/edit")

      assert index_live
             |> form("#agent-form", agent: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#agent-form", agent: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/agent")

      html = render(index_live)
      assert html =~ "Agent updated successfully"
      assert html =~ "some updated instance_id"
    end

    test "deletes agent in listing", %{conn: conn, agent: agent} do
      {:ok, index_live, _html} = live(conn, ~p"/agent")

      assert index_live |> element("#agent-#{agent.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#agent-#{agent.id}")
    end
  end

  describe "Show" do
    setup [:create_agent]

    test "displays agent", %{conn: conn, agent: agent} do
      {:ok, _show_live, html} = live(conn, ~p"/agent/#{agent}")

      assert html =~ "Show Agent"
      assert html =~ agent.instance_id
    end

    test "updates agent within modal", %{conn: conn, agent: agent} do
      {:ok, show_live, _html} = live(conn, ~p"/agent/#{agent}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Agent"

      assert_patch(show_live, ~p"/agent/#{agent}/show/edit")

      assert show_live
             |> form("#agent-form", agent: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#agent-form", agent: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/agent/#{agent}")

      html = render(show_live)
      assert html =~ "Agent updated successfully"
      assert html =~ "some updated instance_id"
    end
  end
end
