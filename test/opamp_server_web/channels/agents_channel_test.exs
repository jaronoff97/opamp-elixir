defmodule OpAMPServerWeb.AgentsChannelTest do
  use OpAMPServerWeb.ChannelCase
  use OpAMPServer.OpAMPCase

  setup do
    # Create a proper proto payload for joining
    agent_id = generate_instance_uid_string()
    payload = build_agent_to_server_with_description()

    {:ok, join_reply, socket} =
      OpAMPServerWeb.UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OpAMPServerWeb.AgentsChannel, "agents:" <> agent_id, payload)

    %{socket: socket, agent_id: agent_id, join_reply: join_reply}
  end

  test "ping replies with server_to_agent", %{socket: socket} do
    ref = push(socket, "ping", %{})
    assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{}
  end

  test "heartbeat replies with server_to_agent", %{socket: socket} do
    payload = build_agent_to_server(%{sequence_num: 2})
    ref = push(socket, "heartbeat", payload)
    assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{}
  end

  test "shout broadcasts to channel", %{socket: socket} do
    push(socket, "shout", %{"hello" => "all"})
    assert_broadcast "shout", %{"hello" => "all"}
  end

  test "replies with the agent's instance_uid as raw bytes", %{join_reply: reply, agent_id: id} do
    assert reply.instance_uid == Ecto.UUID.dump!(id)
  end

  test "join requests full state when promised fields are missing", %{join_reply: reply} do
    # The default capabilities promise health and effective config, which the join payload lacks.
    assert reply.flags == 1
  end

  test "heartbeat requests full state on a sequence gap", %{socket: socket} do
    ref = push(socket, "heartbeat", build_agent_to_server(%{sequence_num: 2}))
    assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{flags: 0}

    ref = push(socket, "heartbeat", build_agent_to_server(%{sequence_num: 5}))
    assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{flags: 1}
  end

  test "offers desired config once, and only to its own agent", %{socket: socket, agent_id: id} do
    other_id = generate_instance_uid_string()
    {:ok, _} = OpAMPServer.Agents.create_agent(%{id: other_id})

    config =
      OpAMPServer.Agents.generate_desired_remote_config(%Opamp.Proto.AgentConfigMap{
        config_map: %{"" => %Opamp.Proto.AgentConfigObject{body: "receivers: {}"}}
      })

    {:ok, _} =
      OpAMPServer.Agents.update_agent(OpAMPServer.Agents.get_agent(other_id), %{
        desired_remote_config: config
      })

    refute_push "", _

    {:ok, _} =
      OpAMPServer.Agents.update_agent(OpAMPServer.Agents.get_agent(id), %{
        desired_remote_config: config
      })

    hash = config.config_hash
    assert_push "", %Opamp.Proto.ServerToAgent{remote_config: %{config_hash: ^hash}}

    ref = push(socket, "heartbeat", build_agent_to_server(%{sequence_num: 2}))
    assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{remote_config: nil}
    refute_push "", _
  end

  @tag :capture_log
  test "does not send a remote config over max_message_size", %{agent_id: id} do
    # test.exs sets max_message_size to 64 KiB.
    config =
      OpAMPServer.Agents.generate_desired_remote_config(%Opamp.Proto.AgentConfigMap{
        config_map: %{
          "" => %Opamp.Proto.AgentConfigObject{body: String.duplicate("a", 64 * 1024)}
        }
      })

    {:ok, _} =
      OpAMPServer.Agents.update_agent(OpAMPServer.Agents.get_agent(id), %{
        desired_remote_config: config
      })

    refute_push "", _
  end

  test "a new connection stops the old channel without deleting the agent", %{
    socket: old_socket,
    agent_id: id
  } do
    Process.flag(:trap_exit, true)
    ref = Process.monitor(old_socket.channel_pid)

    {:ok, _, _} =
      OpAMPServerWeb.UserSocket
      |> socket("other", %{})
      |> subscribe_and_join(
        OpAMPServerWeb.AgentsChannel,
        "agents:" <> id,
        build_agent_to_server_with_description()
      )

    assert_receive {:DOWN, ^ref, _, _, {:shutdown, :superseded}}
    assert OpAMPServer.Agents.get_agent(id)
  end

  describe "connection settings" do
    setup do
      ca_key = X509.PrivateKey.new_ec(:secp256r1)
      ca = X509.Certificate.self_signed(ca_key, "/CN=Test CA", template: :root_ca)

      OpAMPServer.OpAMP.ConnectionSettings.put(%{
        offers: %Opamp.Proto.ConnectionSettingsOffers{
          own_metrics: %Opamp.Proto.TelemetryConnectionSettings{
            destination_endpoint: "https://otlp"
          }
        },
        ca: {ca, ca_key},
        cert_validity_days: 30
      })

      on_exit(fn ->
        Application.delete_env(:opamp_server, OpAMPServer.OpAMP.ConnectionSettings)
      end)
    end

    test "answers a CSR with a certificate and stores it", %{socket: socket, agent_id: id} do
      csr = X509.CSR.new(X509.PrivateKey.new_ec(:secp256r1), "/CN=#{id}")

      ref =
        push(
          socket,
          "heartbeat",
          build_agent_to_server(%{
            sequence_num: 2,
            capabilities: 0x100,
            connection_settings_request: %Opamp.Proto.ConnectionSettingsRequest{
              opamp: %Opamp.Proto.OpAMPConnectionSettingsRequest{
                certificate_request: %Opamp.Proto.CertificateRequest{csr: X509.CSR.to_pem(csr)}
              }
            }
          })
        )

      assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{
        connection_settings: %{opamp: %{certificate: certificate}},
        error_response: nil
      }

      assert certificate.cert =~ "BEGIN CERTIFICATE"
      assert OpAMPServer.Agents.get_certificate(id) == certificate
    end

    @tag :capture_log
    test "answers a bad CSR with a BadRequest", %{socket: socket} do
      ref =
        push(
          socket,
          "heartbeat",
          build_agent_to_server(%{
            sequence_num: 2,
            connection_settings_request: %Opamp.Proto.ConnectionSettingsRequest{
              opamp: %Opamp.Proto.OpAMPConnectionSettingsRequest{
                certificate_request: %Opamp.Proto.CertificateRequest{csr: "garbage"}
              }
            }
          })
        )

      assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{
        connection_settings: nil,
        error_response: %{type: :ServerErrorResponseType_BadRequest}
      }
    end

    test "offers the standing settings until the agent reports their hash", %{socket: socket} do
      # ReportsOwnMetrics
      ref =
        push(socket, "heartbeat", build_agent_to_server(%{sequence_num: 2, capabilities: 0x40}))

      assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{connection_settings: %{hash: hash}}

      ref =
        push(socket, "heartbeat", build_agent_to_server(%{sequence_num: 3, capabilities: 0x40}))

      assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{connection_settings: nil}

      assert is_binary(hash)
    end

    test "advertises the connection settings capabilities", %{socket: socket} do
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{capabilities: capabilities}
      # OffersConnectionSettings | AcceptsConnectionSettingsRequest
      assert Bitwise.band(capabilities, 0x20 + 0x40) == 0x60
    end
  end
end
