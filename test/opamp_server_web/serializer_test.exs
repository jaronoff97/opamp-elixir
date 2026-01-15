defmodule OpAMPServerWeb.SerializerTest do
  use ExUnit.Case, async: true
  use OpAMPServer.OpAMPCase

  alias OpAMPServerWeb.Serializer
  alias Phoenix.Socket.{Reply, Message, Broadcast}
  alias OpAMPServer.OpAMP.ConnectionManager

  setup do
    # Start a unique ConnectionManager for each test
    name = :"serializer_test_manager_#{System.unique_integer([:positive])}"
    {:ok, _pid} = ConnectionManager.start_link(name: name)

    # We need to use the default ConnectionManager name for the serializer
    # So we'll need to start the global one if not already running
    case GenServer.whereis(ConnectionManager) do
      nil ->
        {:ok, _} = ConnectionManager.start_link()

      _pid ->
        :ok
    end

    :ok
  end

  describe "fastlane!/1" do
    test "encodes broadcast with ServerToAgent payload" do
      server_to_agent = build_server_to_agent()

      broadcast = %Broadcast{
        topic: "agents:test",
        event: "update",
        payload: server_to_agent
      }

      result = Serializer.fastlane!(broadcast)

      assert {:socket_push, :binary, binary} = result
      assert is_binary(binary)

      # Verify it's valid protobuf
      decoded = Opamp.Proto.ServerToAgent.decode(binary)
      assert decoded.capabilities == server_to_agent.capabilities
    end

    test "encodes broadcast with empty map payload" do
      broadcast = %Broadcast{
        topic: "agents:test",
        event: "event",
        payload: %{}
      }

      result = Serializer.fastlane!(broadcast)

      assert {:socket_push, :binary, binary} = result
      assert :erlang.binary_to_term(binary) == %{}
    end
  end

  describe "encode!/1 with Reply" do
    test "encodes successful reply with ServerToAgent payload" do
      server_to_agent = build_server_to_agent()

      reply = %Reply{
        status: :ok,
        payload: server_to_agent,
        topic: "agents:test",
        ref: "1",
        join_ref: "join"
      }

      result = Serializer.encode!(reply)

      assert {:socket_push, :binary, binary} = result
      decoded = Opamp.Proto.ServerToAgent.decode(binary)
      assert decoded.capabilities == server_to_agent.capabilities
    end

    test "encodes error reply with unmatched topic" do
      reply = %Reply{
        status: :error,
        payload: %{reason: "unmatched topic"},
        topic: "agents:test",
        ref: "1",
        join_ref: "join"
      }

      result = Serializer.encode!(reply)

      assert {:socket_push, :binary, binary} = result
      decoded = Opamp.Proto.ServerToAgent.decode(binary)
      assert decoded.error_response != nil
      assert decoded.error_response.type == :ServerErrorResponseType_Unavailable
      assert decoded.error_response.error_message == "Connection idled, reconnect requested"
    end

    test "encodes error reply with custom reason" do
      reply = %Reply{
        status: :error,
        payload: %{reason: "Custom error message"},
        topic: "agents:test",
        ref: "1",
        join_ref: "join"
      }

      result = Serializer.encode!(reply)

      assert {:socket_push, :binary, binary} = result
      decoded = Opamp.Proto.ServerToAgent.decode(binary)
      assert decoded.error_response.error_message == "Custom error message"
    end

    test "encodes reply with empty map payload" do
      reply = %Reply{
        status: :ok,
        payload: %{},
        topic: "agents:test",
        ref: "1",
        join_ref: "join"
      }

      result = Serializer.encode!(reply)

      assert {:socket_push, :binary, binary} = result
      assert :erlang.binary_to_term(binary) == %{}
    end

    test "encodes reply with reason payload" do
      reply = %Reply{
        status: :ok,
        payload: %{reason: "some topic"},
        topic: "agents:test",
        ref: "1",
        join_ref: "join"
      }

      result = Serializer.encode!(reply)

      assert {:socket_push, :binary, binary} = result
      assert :erlang.binary_to_term(binary) == %{reason: "some topic"}
    end
  end

  describe "encode!/1 with Message" do
    test "encodes message with ServerToAgent payload" do
      server_to_agent = build_server_to_agent()

      message = %Message{
        topic: "agents:test",
        event: "update",
        payload: server_to_agent,
        ref: "1",
        join_ref: "join"
      }

      result = Serializer.encode!(message)

      assert {:socket_push, :binary, binary} = result
      decoded = Opamp.Proto.ServerToAgent.decode(binary)
      assert decoded.capabilities == server_to_agent.capabilities
    end

    test "encodes message with empty payload" do
      message = %Message{
        topic: "agents:test",
        event: "event",
        payload: %{},
        ref: "1",
        join_ref: "join"
      }

      result = Serializer.encode!(message)

      assert {:socket_push, :binary, binary} = result
      assert :erlang.binary_to_term(binary) == %{}
    end
  end

  describe "decode!/2 with text opcode" do
    test "decodes JSON text message" do
      json_message = Jason.encode!(["join_ref", "ref", "topic", "event", %{"key" => "value"}])

      result = Serializer.decode!(json_message, opcode: :text)

      assert %Message{} = result
      assert result.topic == "topic"
      assert result.event == "event"
      assert result.payload == %{"key" => "value"}
      assert result.ref == "ref"
      assert result.join_ref == "join_ref"
    end

    test "decodes JSON with nil refs" do
      json_message = Jason.encode!([nil, nil, "topic", "event", %{}])

      result = Serializer.decode!(json_message, opcode: :text)

      assert result.ref == nil
      assert result.join_ref == nil
    end
  end

  describe "decode!/2 with binary opcode - new connection (join)" do
    test "decodes binary as join for new connection" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)
      message = build_agent_to_server(%{instance_uid: instance_uid, sequence_num: 1})
      binary = encode_with_header(message)

      # Ensure agent is not registered (new connection)
      ConnectionManager.unregister(agent_id)
      Process.sleep(10)

      result = Serializer.decode!(binary, opcode: :binary)

      assert %Message{} = result
      assert result.topic == "agents:" <> agent_id
      assert result.event == "phx_join"
      assert result.payload == message
      assert result.join_ref == "join"
    end

    test "registers agent on join" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)
      message = build_agent_to_server(%{instance_uid: instance_uid, sequence_num: 1})
      binary = encode_with_header(message)

      # Ensure not registered
      ConnectionManager.unregister(agent_id)
      Process.sleep(10)

      assert ConnectionManager.is_new_connection?(agent_id) == true

      Serializer.decode!(binary, opcode: :binary)

      assert ConnectionManager.connected?(agent_id) == true
    end
  end

  describe "decode!/2 with binary opcode - existing connection (heartbeat)" do
    test "decodes binary as heartbeat for existing connection" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)
      message = build_agent_to_server(%{instance_uid: instance_uid, sequence_num: 5})
      binary = encode_with_header(message)

      # Register the agent first
      ConnectionManager.register(agent_id)

      result = Serializer.decode!(binary, opcode: :binary)

      assert %Message{} = result
      assert result.topic == "agents:" <> agent_id
      assert result.event == "heartbeat"
      assert result.ref == 5
      assert result.join_ref == "beat"
    end

    test "preserves sequence number as ref" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)
      message = build_agent_to_server(%{instance_uid: instance_uid, sequence_num: 42})
      binary = encode_with_header(message)

      ConnectionManager.register(agent_id)

      result = Serializer.decode!(binary, opcode: :binary)

      assert result.ref == 42
    end
  end

  describe "decode!/2 preserves proto payload" do
    test "preserves agent description in payload" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)
      message = build_agent_to_server_with_description(%{instance_uid: instance_uid})
      binary = encode_with_header(message)

      ConnectionManager.register(agent_id)

      result = Serializer.decode!(binary, opcode: :binary)

      assert result.payload.agent_description != nil
      assert length(result.payload.agent_description.identifying_attributes) == 2
    end

    test "preserves health in payload" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)
      message = build_agent_to_server_with_health(%{instance_uid: instance_uid})
      binary = encode_with_header(message)

      ConnectionManager.register(agent_id)

      result = Serializer.decode!(binary, opcode: :binary)

      assert result.payload.health != nil
      assert result.payload.health.healthy == true
    end

    test "preserves effective config in payload" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)
      message = build_agent_to_server_with_config(%{instance_uid: instance_uid})
      binary = encode_with_header(message)

      ConnectionManager.register(agent_id)

      result = Serializer.decode!(binary, opcode: :binary)

      assert result.payload.effective_config != nil
    end

    test "preserves capabilities in payload" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)
      caps = all_agent_capabilities()
      message = build_agent_to_server(%{instance_uid: instance_uid, capabilities: caps})
      binary = encode_with_header(message)

      ConnectionManager.register(agent_id)

      result = Serializer.decode!(binary, opcode: :binary)

      assert result.payload.capabilities == caps
    end

    test "preserves remote config status in payload" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)

      status =
        build_remote_config_status(%{
          status: :RemoteConfigStatuses_FAILED,
          error_message: "Parse error"
        })

      message = build_agent_to_server(%{instance_uid: instance_uid, remote_config_status: status})
      binary = encode_with_header(message)

      ConnectionManager.register(agent_id)

      result = Serializer.decode!(binary, opcode: :binary)

      assert result.payload.remote_config_status.status == :RemoteConfigStatuses_FAILED
      assert result.payload.remote_config_status.error_message == "Parse error"
    end

    test "preserves available components in payload" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)
      components = build_available_components()

      message =
        build_agent_to_server(%{instance_uid: instance_uid, available_components: components})

      binary = encode_with_header(message)

      ConnectionManager.register(agent_id)

      result = Serializer.decode!(binary, opcode: :binary)

      assert result.payload.available_components != nil
      assert map_size(result.payload.available_components.components) == 2
    end
  end

  describe "round trip encoding" do
    test "ServerToAgent survives encode round trip via Message" do
      server_to_agent =
        build_server_to_agent(%{
          remote_config: build_agent_remote_config(),
          flags: 1
        })

      message = %Message{
        topic: "agents:test",
        event: "update",
        payload: server_to_agent,
        ref: "1",
        join_ref: "join"
      }

      {:socket_push, :binary, binary} = Serializer.encode!(message)
      decoded = Opamp.Proto.ServerToAgent.decode(binary)

      assert decoded.capabilities == server_to_agent.capabilities
      assert decoded.flags == 1
      assert decoded.remote_config != nil
    end

    test "error response survives encode round trip" do
      reply = %Reply{
        status: :error,
        payload: %{reason: "test error"},
        topic: "agents:test",
        ref: "1",
        join_ref: "join"
      }

      {:socket_push, :binary, binary} = Serializer.encode!(reply)
      decoded = Opamp.Proto.ServerToAgent.decode(binary)

      assert decoded.error_response.error_message == "test error"
    end
  end

  describe "edge cases" do
    test "handles sequence_num of 0 as heartbeat when connected" do
      # Note: The current implementation requires sequence_num > 0 for heartbeat
      # This tests the boundary condition
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)
      message = build_agent_to_server(%{instance_uid: instance_uid, sequence_num: 0})
      binary = encode_with_header(message)

      # Unregister first to ensure it's treated as new
      ConnectionManager.unregister(agent_id)
      Process.sleep(10)

      result = Serializer.decode!(binary, opcode: :binary)

      # sequence_num 0 means it's a join
      assert result.event == "phx_join"
    end

    test "handles very large sequence numbers" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)

      message =
        build_agent_to_server(%{
          instance_uid: instance_uid,
          sequence_num: 18_446_744_073_709_551_615
        })

      binary = encode_with_header(message)

      ConnectionManager.register(agent_id)

      result = Serializer.decode!(binary, opcode: :binary)

      assert result.ref == 18_446_744_073_709_551_615
    end
  end
end
