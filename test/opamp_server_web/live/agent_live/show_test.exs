defmodule OpAMPServerWeb.AgentLive.ShowTest do
  use OpAMPServerWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpAMPServer.AgentsFixtures

  alias OpAMPServer.Agents
  alias OpAMPServer.OpAMP.ConnectionSettings

  # An agent like the OpAMP Bridge: two managed collectors, "a" with two pods and "b" with one.
  defp bridge_agent(attrs \\ %{}) do
    agent_fixture(
      Map.merge(
        %{
          effective_config:
            effective_config_fixture(%{
              "default/a" => pipeline_collector_body("a"),
              "default/b" => collector_body("b")
            }),
          component_health:
            health_fixture(%{"default/a" => ["a-pod-1", "a-pod-2"], "default/b" => ["b-pod-1"]}),
          capabilities: 0x1 + 0x2 + 0x4 + 0x800
        },
        attrs
      )
    )
  end

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

  defp node_id(graph, id), do: "[id='#{graph}-node-#{id}']"

  describe "mount" do
    test "redirects to the agent list for an unknown agent", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/agents", flash: %{"error" => _}}}} =
               live(conn, ~p"/agents/#{Ecto.UUID.generate()}")
    end

    test "shows the agent's name, instance, status and kind", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, html} = live(conn, ~p"/agents/#{agent.id}")

      assert html =~ "test-service"
      assert html =~ agent.id
      assert html =~ "OpAMP Bridge"
      assert html =~ "Healthy"
      assert has_element?(view, "nav a[aria-current=page]", "Agents")
    end

    test "every tab renders an agent that has not reported anything", %{conn: conn} do
      {:ok, agent} = Agents.create_agent(%{id: Ecto.UUID.generate()})

      for tab <- ["", "/config", "/pipeline", "/connection"] do
        {:ok, _view, html} = live(conn, "/agents/#{agent.id}#{tab}")
        assert html =~ agent.id, "tab #{tab} should render"
      end
    end
  end

  describe "tabs" do
    test "each tab link opens its tab and marks it as selected", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      for tab <- ~w(config pipeline connection) do
        view |> element("#tab-#{tab}") |> render_click()
        assert_patch(view, "/agents/#{agent.id}/#{tab}?object=default%2Fa")
        assert has_element?(view, "#tab-#{tab}[aria-selected=true]")
      end

      view |> element("#tab-overview") |> render_click()
      assert_patch(view, ~p"/agents/#{agent.id}")
    end
  end

  describe "overview" do
    test "shows health, identity, details and capabilities", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      assert view |> element("#health") |> render() =~ "Jan 2, 2026 03:04:05 UTC"
      assert view |> element("#identity") |> render() =~ "test-service"
      assert view |> element("#details") |> render() =~ "linux"

      capabilities = view |> element("#capabilities") |> render()

      for name <- ~w(ReportsStatus AcceptsRemoteConfig ReportsEffectiveConfig ReportsHealth) do
        assert capabilities =~ name
      end
    end

    test "shows each config object with its pods", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      a = view |> element("[id='object-default/a']") |> render()
      assert a =~ "managed"
      assert a =~ "a-pod-1"
      assert a =~ "a-pod-2"
      assert a =~ "Running"
      refute a =~ "b-pod-1"
    end

    test "marks read-only collectors, and names the empty key (default)", %{conn: conn} do
      agent =
        bridge_agent(%{
          effective_config:
            effective_config_fixture(%{
              "default/unmanaged" => collector_body("unmanaged", %{}),
              "" => "receivers: {}"
            })
        })

      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      assert view |> element("[id='object-default/unmanaged']") |> render() =~ "read-only"
      assert view |> element("[id='object-']") |> render() =~ "(default)"
    end

    test "says when a collector has no health entry yet", %{conn: conn} do
      agent = bridge_agent(%{component_health: health_fixture(%{"default/a" => ["a-pod-1"]})})
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      assert view |> element("[id='object-default/b']") |> render() =~ "No health reported yet."
    end

    test "shows the current pods after a rollout replaces a pod", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      {:ok, _} =
        Agents.update_agent(agent, %{
          component_health: health_fixture(%{"default/a" => ["a-pod-3"], "default/b" => []})
        })

      a = view |> element("[id='object-default/a']") |> render()
      assert a =~ "a-pod-3"
      refute a =~ "a-pod-1"
    end

    test "shows a new collector when the agent reports one", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      {:ok, _} =
        Agents.update_agent(agent, %{
          effective_config: effective_config_fixture(%{"default/c" => collector_body("c")})
        })

      assert has_element?(view, "[id='object-default/c']")
      refute has_element?(view, "[id='object-default/a']")
    end
  end

  describe "config" do
    test "selects the first object, and lists every object", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}/config")

      assert has_element?(
               view,
               "nav[aria-label='Config objects'] a[aria-current=true]",
               "default/a"
             )

      assert has_element?(view, "nav[aria-label='Config objects'] a", "default/b")
      assert view |> element("textarea") |> render() =~ "name: a"
    end

    test "the object parameter selects an object, and an unknown one falls back", %{conn: conn} do
      agent = bridge_agent()

      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}/config?object=default/b")
      assert view |> element("textarea") |> render() =~ "name: b"

      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}/config?object=nope")
      assert view |> element("textarea") |> render() =~ "name: a"
    end

    test "a click in the menu switches the object", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}/config")

      view |> element("nav[aria-label='Config objects'] a", "default/b") |> render_click()

      assert_patch(view, "/agents/#{agent.id}/config?object=default%2Fb")
      assert view |> element("textarea") |> render() =~ "name: b"
    end

    test "sends the edited object together with the other objects", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}/config")

      html = view |> form("#config-form", config: %{body: "edited"}) |> render_submit()

      assert html =~ "Sent the new config to the agent."
      desired = Agents.get_agent!(agent.id).desired_remote_config
      assert Map.keys(desired.config.config_map) == ["default/a", "default/b"]
      assert desired.config.config_map["default/a"].body == "edited"
      assert desired.config.config_map["default/b"].body == collector_body("b")

      assert desired.config_hash ==
               Agents.generate_desired_remote_config(desired.config).config_hash
    end

    test "a read-only collector cannot be sent", %{conn: conn} do
      agent =
        bridge_agent(%{
          effective_config: effective_config_fixture(%{"default/u" => collector_body("u", %{})})
        })

      {:ok, view, html} = live(conn, ~p"/agents/#{agent.id}/config")

      assert html =~ "This collector is read-only."
      assert has_element?(view, "#config-form button[disabled]")
    end

    test "shows the error when the agent could not apply the config", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}/config")
      view |> form("#config-form", config: %{body: "edited"}) |> render_submit()
      agent = Agents.get_agent!(agent.id)

      {:ok, _} =
        Agents.update_agent(agent, %{
          remote_config_status: %Opamp.Proto.RemoteConfigStatus{
            last_remote_config_hash: agent.desired_remote_config.config_hash,
            status: :RemoteConfigStatuses_FAILED,
            error_message: "unknown exporter: nope"
          }
        })

      assert view |> element("#config-editor [role=alert]") |> render() =~
               "unknown exporter: nope"

      assert has_element?(view, "#flash-error", "unknown exporter: nope")
    end

    test "shows an empty state without config objects", %{conn: conn} do
      {:ok, agent} = Agents.create_agent(%{id: Ecto.UUID.generate()})
      {:ok, _view, html} = live(conn, ~p"/agents/#{agent.id}/config")

      assert html =~ "No config reported"
    end
  end

  describe "pipeline" do
    test "opens the first object with pipelines, as a graph", %{conn: conn} do
      agent =
        bridge_agent(%{
          effective_config:
            effective_config_fixture(%{
              "default/0-empty" => collector_body("empty"),
              "default/a" => pipeline_collector_body("a")
            })
        })

      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}/pipeline")

      for id <-
            ~w(receiver:otlp processor:traces:memory_limiter processor:traces:batch exporter:debug) do
        assert has_element?(view, node_id("pipeline-default/a", id)), "#{id} should be a node"
      end

      assert has_element?(
               view,
               "path[id='pipeline-default/a-edge-receiver:otlp->processor:traces:memory_limiter']"
             )
    end

    test "a click on a component shows its config, and a second click hides it", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}/pipeline")
      otlp = "#{node_id("pipeline-default/a", "receiver:otlp")} button"

      view |> element(otlp) |> render_click()
      assert view |> element("#component-config") |> render() =~ "0.0.0.0:4317"

      view |> element(otlp) |> render_click()
      refute has_element?(view, "#component-config")
    end

    test "says when a config has no pipelines", %{conn: conn} do
      agent = bridge_agent()
      {:ok, _view, html} = live(conn, ~p"/agents/#{agent.id}/pipeline?object=default/b")

      assert html =~ "This config has no pipelines."
    end
  end

  describe "connection" do
    setup do
      on_exit(fn -> Application.delete_env(:opamp_server, ConnectionSettings) end)
    end

    test "says when the server offers nothing and no certificate is issued", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}/connection")

      assert view |> element("#connection-settings") |> render() =~ "The server offers nothing"

      assert view |> element("#client-certificate") |> render() =~
               "has not issued a certificate"
    end

    test "shows the offer for this agent and its issued certificate", %{conn: conn} do
      ca_key = X509.PrivateKey.new_ec(:secp256r1)
      ca = X509.Certificate.self_signed(ca_key, "/CN=Test CA", template: :root_ca)

      ConnectionSettings.put(%{
        offers: %Opamp.Proto.ConnectionSettingsOffers{
          own_metrics: %Opamp.Proto.TelemetryConnectionSettings{
            destination_endpoint: "https://otlp:4318"
          }
        },
        ca: {ca, ca_key},
        cert_validity_days: 30
      })

      # ReportsOwnMetrics
      agent = bridge_agent(%{capabilities: 0x40})
      csr = X509.CSR.new(X509.PrivateKey.new_ec(:secp256r1), "/CN=#{agent.id}")
      {:ok, certificate} = ConnectionSettings.sign_csr(X509.CSR.to_pem(csr), agent.id)
      {:ok, _} = Agents.put_certificate(agent.id, certificate)

      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}/connection")

      assert view |> element("#connection-settings") |> render() =~ "https://otlp:4318"
      certificate = view |> element("#client-certificate") |> render()
      assert certificate =~ "/CN=#{agent.id}"
      assert certificate =~ "/CN=Test CA"
      assert view |> element("#connection-capabilities") |> render() =~ "ReportsOwnMetrics"
    end
  end

  describe "live updates" do
    test "says when the agent applied the config", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      remote_config_status(agent, :RemoteConfigStatuses_APPLIED)

      assert render(view) =~ "The agent applied the config."
    end

    test "says when the agent is applying the config", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      remote_config_status(agent, :RemoteConfigStatuses_APPLYING)

      assert render(view) =~ "The agent is applying the config…"
    end

    test "does not repeat the status message for the same config", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")
      agent = remote_config_status(agent, :RemoteConfigStatuses_APPLIED)
      render_click(view, "lv:clear-flash", %{"key" => "info"})

      # A heartbeat with the same status and hash.
      {:ok, _} = Agents.update_agent(agent, %{component_health: health_fixture(%{})})

      refute render(view) =~ "The agent applied the config."
    end

    test "goes back to the agent list when the agent disconnects", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      {:ok, _} = Agents.delete_agent(agent)

      assert_redirect(view, ~p"/agents")
    end

    test "stays on the page when the agent reconnects", %{conn: conn} do
      agent = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      Phoenix.PubSub.broadcast(
        OpAMPServer.PubSub,
        "agents:" <> agent.id,
        {:agent_superseded, self()}
      )

      send(view.pid, :tick)

      assert render(view) =~ agent.id
    end

    test "ignores updates of other agents", %{conn: conn} do
      agent = bridge_agent()
      other = bridge_agent()
      {:ok, view, _html} = live(conn, ~p"/agents/#{agent.id}")

      {:ok, _} = Agents.delete_agent(other)

      assert render(view) =~ agent.id
    end
  end
end
