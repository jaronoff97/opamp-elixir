defmodule OpAMPServerWeb.AgentLive.ShowTest do
  use OpAMPServerWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpAMPServer.AgentsFixtures

  alias OpAMPServer.Agents

  # An agent like the OpAMP Bridge: two managed collectors, "a" with two pods and "b" with one.
  defp bridge_agent(attrs \\ %{}) do
    agent_fixture(
      Map.merge(
        %{
          effective_config:
            effective_config_fixture(%{
              "default/a" => collector_body("a"),
              "default/b" => collector_body("b")
            }),
          component_health:
            health_fixture(%{"default/a" => ["a-pod-1", "a-pod-2"], "default/b" => ["b-pod-1"]})
        },
        attrs
      )
    )
  end

  defp select(view, collector), do: view |> element("#instance td", collector) |> render_click()

  defp remote_config_status(agent, status, error_message \\ "") do
    {:ok, agent} =
      Agents.update_agent(agent, %{
        remote_config_status: %Opamp.Proto.RemoteConfigStatus{
          last_remote_config_hash: :crypto.strong_rand_bytes(16),
          status: status,
          error_message: error_message
        }
      })

    agent
  end

  describe "mount" do
    test "redirects to the index for an unknown agent", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/#{Ecto.UUID.generate()}")
    end

    test "shows the agent's heartbeat, health and description", %{conn: conn} do
      agent = bridge_agent()
      {:ok, _view, html} = live(conn, ~p"/#{agent}")

      assert html =~ "Agent #{agent.id}"
      assert html =~ "Last Heartbeat: January 2, 2026 03:04:05 AM UTC"
      assert html =~ "Healthy? true"
      assert html =~ "Service Name: test-service"
      assert html =~ "Host Name: test-host"
      assert html =~ "OS Family: linux"
    end

    test "shows an agent that has not reported health, config or a description", %{conn: conn} do
      {:ok, agent} = Agents.create_agent(%{id: Ecto.UUID.generate()})

      {:ok, view, html} = live(conn, ~p"/#{agent}")

      assert html =~ "Agent #{agent.id}"
      refute has_element?(view, "#instance td")
    end
  end

  describe "collector table" do
    test "lists each collector with its health", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      a = view |> element("#instance tr", "default/a") |> render()
      assert a =~ "2/2"
      assert a =~ "January 2, 2026 03:04:05 AM"
      assert view |> element("#instance tr", "default/b") |> render() =~ "1/1"
    end

    test "marks which collectors the server can modify", %{conn: conn} do
      agent =
        bridge_agent(%{
          effective_config:
            effective_config_fixture(%{
              "default/managed" => collector_body("managed"),
              "default/unmanaged" => collector_body("unmanaged", %{})
            })
        })

      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      assert view |> element("#instance tr", "default/managed") |> render() =~ "✅"
      assert view |> element("#instance tr", "default/unmanaged") |> render() =~ "🚫"
    end

    test "names the empty config key (default)", %{conn: conn} do
      agent =
        agent_fixture(%{effective_config: effective_config_fixture(%{"" => "receivers: {}"})})

      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      assert has_element?(view, "#instance td", "(default)")
    end

    test "shows a collector that has no health entry yet", %{conn: conn} do
      agent = bridge_agent(%{component_health: health_fixture(%{"default/a" => ["a-pod-1"]})})
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      assert has_element?(view, "#instance td", "default/b")
    end
  end

  describe "selecting a collector" do
    test "shows its pods and its config", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      html = select(view, "default/a")

      assert html =~ "Configuration: default/a"
      assert has_element?(view, "#pods td", "a-pod-1")
      assert has_element?(view, "#pods td", "a-pod-2")
      refute has_element?(view, "#pods td", "b-pod-1")
      assert view |> element("#pods tr", "a-pod-1") |> render() =~ "Running"
      assert view |> element("textarea") |> render() =~ "name: a"
    end

    test "a second click on the same collector closes it", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      select(view, "default/a")
      select(view, "default/a")

      refute has_element?(view, "#pods")
      refute has_element?(view, "textarea")
    end

    test "a click on another collector switches to it", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      select(view, "default/a")
      html = select(view, "default/b")

      assert html =~ "Configuration: default/b"
      assert has_element?(view, "#pods td", "b-pod-1")
      refute has_element?(view, "#pods td", "a-pod-1")
    end

    test "works for a collector that has no health entry yet", %{conn: conn} do
      agent = bridge_agent(%{component_health: health_fixture(%{"default/a" => ["a-pod-1"]})})
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      assert select(view, "default/b") =~ "Configuration: default/b"
      refute has_element?(view, "#pods td")
    end

    test "a click on a pod shows its name", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      select(view, "default/a")

      assert view |> element("#pods td", "a-pod-2") |> render_click() =~ "clicked a-pod-2"
    end
  end

  describe "saving a config" do
    test "sends the edited collector together with the other collectors", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      select(view, "default/a")

      html =
        view
        |> form("form[phx-submit=save]", agent: %{effective_config: "edited"})
        |> render_submit()

      assert html =~ "Updated. Running…"
      refute has_element?(view, "textarea")

      desired = Agents.get_agent!(agent.id).desired_remote_config
      assert Map.keys(desired.config.config_map) == ["default/a", "default/b"]
      assert desired.config.config_map["default/a"].body == "edited"
      assert desired.config.config_map["default/b"].body == collector_body("b")

      assert desired.config_hash ==
               Agents.generate_desired_remote_config(desired.config).config_hash
    end
  end

  describe "live updates" do
    test "shows the current pods after a rollout replaces a pod", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")
      select(view, "default/a")

      {:ok, _} =
        Agents.update_agent(agent, %{
          component_health: health_fixture(%{"default/a" => ["a-pod-3"], "default/b" => []})
        })

      assert has_element?(view, "#pods td", "a-pod-3")
      refute has_element?(view, "#pods td", "a-pod-1")
      assert has_element?(view, "textarea")
    end

    test "shows a new collector when the agent reports one", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      {:ok, _} =
        Agents.update_agent(agent, %{
          effective_config: effective_config_fixture(%{"default/c" => collector_body("c")})
        })

      assert has_element?(view, "#instance td", "default/c")
      refute has_element?(view, "#instance td", "default/a")
    end

    test "says when the agent applied the config", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      remote_config_status(agent, :RemoteConfigStatuses_APPLIED)

      assert render(view) =~ "Success applying!"
    end

    test "says when the agent is applying the config", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      remote_config_status(agent, :RemoteConfigStatuses_APPLYING)

      assert render(view) =~ "applying..."
    end

    test "shows the error when the agent could not apply the config", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      remote_config_status(agent, :RemoteConfigStatuses_FAILED, "unknown exporter: nope")

      # The error flash has the "Error!" title.
      assert view |> element("[role=alert]", "unknown exporter: nope") |> render() =~ "Error!"
    end

    test "does not repeat the status message for the same config", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")
      agent = remote_config_status(agent, :RemoteConfigStatuses_APPLIED)
      render_click(view, "lv:clear-flash", %{"key" => "info"})

      # A heartbeat with the same status and hash.
      {:ok, _} = Agents.update_agent(agent, %{component_health: health_fixture(%{})})

      refute render(view) =~ "Success applying!"
    end

    test "goes back to the index when the agent disconnects", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      {:ok, _} = Agents.delete_agent(agent)

      assert_redirect(view, ~p"/")
    end

    test "stays on the page when the agent reconnects", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      Phoenix.PubSub.broadcast(
        OpAMPServer.PubSub,
        "agents:" <> agent.id,
        {:agent_superseded, self()}
      )

      assert render(view) =~ "Agent #{agent.id}"
    end

    test "ignores updates of other agents", %{conn: conn} do
      agent = bridge_agent()
      other = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/#{agent}")

      {:ok, _} = Agents.delete_agent(other)

      assert render(view) =~ "Agent #{agent.id}"
    end
  end
end
