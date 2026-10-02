defmodule OpAMPServer.OpAMP.ProtocolTest do
  @moduledoc """
  Integration tests for the OpAMP Protocol module.
  Tests the full flow of processing messages through the protocol layer.
  """

  use ExUnit.Case, async: true
  use OpAMPServer.OpAMPCase

  alias OpAMPServer.OpAMP.Protocol
  alias OpAMPServer.OpAMP.Protocol.Decoder

  describe "build_response/2" do
    test "builds response with default capabilities" do
      agent_id = generate_instance_uid_string()

      result = Protocol.build_response(agent_id)

      assert %Opamp.Proto.ServerToAgent{} = result
      assert result.instance_uid == agent_id
      assert result.capabilities == Protocol.server_capabilities()
    end

    test "builds response with remote config" do
      agent_id = generate_instance_uid_string()
      remote_config = build_agent_remote_config()

      result = Protocol.build_response(agent_id, remote_config: remote_config)

      assert result.remote_config == remote_config
    end

    test "builds response with flags" do
      agent_id = generate_instance_uid_string()

      result = Protocol.build_response(agent_id, flags: 3)

      assert result.flags == 3
    end
  end

  describe "build_error_response/1" do
    test "builds unavailable error" do
      result = Protocol.build_error_response(:unmatched_topic)

      assert result.error_response.type == :ServerErrorResponseType_Unavailable
    end

    test "builds bad request error" do
      result = Protocol.build_error_response({:bad_request, "Invalid format"})

      assert result.error_response.type == :ServerErrorResponseType_BadRequest
      assert result.error_response.error_message == "Invalid format"
    end
  end

  describe "encode/1" do
    test "encodes ServerToAgent to binary" do
      message = build_server_to_agent()

      result = Protocol.encode(message)

      assert is_binary(result)
      decoded = decode_server_to_agent(result)
      assert decoded.capabilities == message.capabilities
    end
  end

  describe "server_capabilities/0" do
    test "returns server capabilities bitmask" do
      result = Protocol.server_capabilities()

      assert is_integer(result)
      assert result > 0
    end
  end

  describe "agent_has_capability?/2" do
    test "checks agent capabilities" do
      import Bitwise
      # ReportsStatus | AcceptsRemoteConfig
      agent = %{capabilities: 1 ||| 2}

      assert Protocol.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus
             )

      refute Protocol.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHealth
             )
    end
  end

  describe "attributes_to_map/2" do
    test "converts attributes to map" do
      attributes = [
        build_key_value("key1", "value1"),
        build_key_value("key2", "value2")
      ]

      result = Protocol.attributes_to_map(attributes)

      assert result == %{"key1" => "value1", "key2" => "value2"}
    end
  end

  describe "full message processing flow" do
    test "processes join and subsequent heartbeats" do
      instance_uid = generate_instance_uid()
      agent_id = Ecto.UUID.load!(instance_uid)

      # First message - should be join
      join_message = build_agent_to_server(%{instance_uid: instance_uid, sequence_num: 1})
      join_binary = encode_with_header(join_message)

      {:ok, _, ^agent_id} = Decoder.decode_agent_message(join_binary)

      # Subsequent messages - should be regular messages
      for seq <- 2..5 do
        heartbeat = build_agent_to_server(%{instance_uid: instance_uid, sequence_num: seq})
        binary = encode_with_header(heartbeat)

        {:ok, proto, ^agent_id} = Decoder.decode_agent_message(binary)
        assert proto.sequence_num == seq
      end
    end

    test "handles agent with changing health status" do
      instance_uid = generate_instance_uid()

      # Initial healthy status
      healthy_message =
        build_agent_to_server_with_health(%{
          instance_uid: instance_uid,
          health: build_component_health(%{healthy: true, status: "Running"})
        })

      binary1 = encode_with_header(healthy_message)

      {:ok, proto1, agent_id} = Decoder.decode_agent_message(binary1)
      assert proto1.health.healthy == true

      # Status changes to unhealthy
      unhealthy_message =
        build_agent_to_server_with_health(%{
          instance_uid: instance_uid,
          sequence_num: 2,
          health:
            build_component_health(%{
              healthy: false,
              status: "Error",
              last_error: "Connection timeout"
            })
        })

      binary2 = encode_with_header(unhealthy_message)

      {:ok, proto2, ^agent_id} = Decoder.decode_agent_message(binary2)
      assert proto2.health.healthy == false
      assert proto2.health.last_error == "Connection timeout"
    end

    test "handles agent with config updates" do
      instance_uid = generate_instance_uid()

      # Initial config
      config1 =
        build_effective_config(%{
          config_map:
            build_agent_config_map(%{
              "collector.yaml" => build_agent_config_file("version: 1")
            })
        })

      message1 =
        build_agent_to_server_with_config(%{
          instance_uid: instance_uid,
          effective_config: config1
        })

      binary1 = encode_with_header(message1)

      {:ok, proto1, agent_id} = Decoder.decode_agent_message(binary1)
      assert proto1.effective_config.config_map.config_map["collector.yaml"].body == "version: 1"

      # Updated config
      config2 =
        build_effective_config(%{
          config_map:
            build_agent_config_map(%{
              "collector.yaml" => build_agent_config_file("version: 2")
            })
        })

      message2 =
        build_agent_to_server_with_config(%{
          instance_uid: instance_uid,
          sequence_num: 2,
          effective_config: config2
        })

      binary2 = encode_with_header(message2)

      {:ok, proto2, ^agent_id} = Decoder.decode_agent_message(binary2)
      assert proto2.effective_config.config_map.config_map["collector.yaml"].body == "version: 2"
    end

    test "handles remote config status progression" do
      instance_uid = generate_instance_uid()

      statuses = [
        {:RemoteConfigStatuses_UNSET, ""},
        {:RemoteConfigStatuses_APPLYING, ""},
        {:RemoteConfigStatuses_APPLIED, ""},
        {:RemoteConfigStatuses_FAILED, "Parse error on line 42"}
      ]

      # First message creates the connection
      first_status = build_remote_config_status(%{status: :RemoteConfigStatuses_UNSET})

      first_msg =
        build_agent_to_server(%{
          instance_uid: instance_uid,
          sequence_num: 1,
          remote_config_status: first_status
        })

      {:ok, _, agent_id} = Decoder.decode_agent_message(encode_with_header(first_msg))

      # Process remaining status updates
      for {{status, error}, seq} <- Enum.with_index(tl(statuses), 2) do
        config_status = build_remote_config_status(%{status: status, error_message: error})

        message =
          build_agent_to_server(%{
            instance_uid: instance_uid,
            sequence_num: seq,
            remote_config_status: config_status
          })

        {:ok, proto, ^agent_id} = Decoder.decode_agent_message(encode_with_header(message))
        assert proto.remote_config_status.status == status
      end
    end
  end

  describe "protocol edge cases" do
    test "handles agent with all capabilities" do
      message = build_agent_to_server(%{capabilities: all_agent_capabilities()})
      binary = encode_with_header(message)

      {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)

      # Verify all capabilities are preserved
      assert Protocol.agent_has_capability?(
               proto,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus
             )

      assert Protocol.agent_has_capability?(
               proto,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHealth
             )

      assert Protocol.agent_has_capability?(
               proto,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsAvailableComponents
             )

      assert Protocol.agent_has_capability?(
               proto,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHeartbeat
             )
    end

    test "handles agent with available components" do
      components = build_available_components()
      message = build_agent_to_server(%{available_components: components})
      binary = encode_with_header(message)

      {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)

      assert proto.available_components != nil
      assert map_size(proto.available_components.components) == 2
    end

    test "handles agent disconnect message" do
      disconnect = %Opamp.Proto.AgentDisconnect{}
      message = build_agent_to_server(%{agent_disconnect: disconnect})
      binary = encode_with_header(message)

      {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)

      assert proto.agent_disconnect != nil
    end

    test "handles empty agent description" do
      empty_desc = %Opamp.Proto.AgentDescription{
        identifying_attributes: [],
        non_identifying_attributes: []
      }

      message = build_agent_to_server(%{agent_description: empty_desc})
      binary = encode_with_header(message)

      {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)

      assert proto.agent_description.identifying_attributes == []
    end

    test "handles deeply nested component health" do
      # Create nested component health structure
      level3 = build_component_health(%{status: "Level 3"})

      level2 =
        build_component_health(%{
          status: "Level 2",
          component_health_map: %{"level3" => level3}
        })

      level1 =
        build_component_health(%{
          status: "Level 1",
          component_health_map: %{"level2" => level2}
        })

      root =
        build_component_health(%{
          status: "Root",
          component_health_map: %{"level1" => level1}
        })

      message = build_agent_to_server(%{health: root})
      binary = encode_with_header(message)

      {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)

      assert proto.health.component_health_map["level1"].component_health_map["level2"].component_health_map[
               "level3"
             ].status == "Level 3"
    end
  end
end
