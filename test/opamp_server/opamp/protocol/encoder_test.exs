defmodule OpAMPServer.OpAMP.Protocol.EncoderTest do
  use ExUnit.Case, async: true
  use OpAMPServer.OpAMPCase

  alias OpAMPServer.OpAMP.Protocol.Encoder

  describe "build_server_to_agent/2" do
    test "builds minimal ServerToAgent with defaults" do
      agent_id = generate_instance_uid_string()

      result = Encoder.build_server_to_agent(agent_id)

      assert %Opamp.Proto.ServerToAgent{} = result
      assert result.instance_uid == agent_id
      assert result.capabilities == Helpers.server_capabilities()
      assert result.error_response == nil
      assert result.remote_config == nil
    end

    test "builds ServerToAgent with custom capabilities" do
      agent_id = generate_instance_uid_string()
      # AcceptsStatus | OffersRemoteConfig | AcceptsEffectiveConfig
      custom_caps = 7

      result = Encoder.build_server_to_agent(agent_id, capabilities: custom_caps)

      assert result.capabilities == 7
    end

    test "builds ServerToAgent with remote config" do
      agent_id = generate_instance_uid_string()
      remote_config = build_agent_remote_config()

      result = Encoder.build_server_to_agent(agent_id, remote_config: remote_config)

      assert result.remote_config == remote_config
      assert result.remote_config.config != nil
    end

    test "builds ServerToAgent with flags" do
      agent_id = generate_instance_uid_string()

      result = Encoder.build_server_to_agent(agent_id, flags: 1)

      assert result.flags == 1
    end

    test "builds ServerToAgent with error response" do
      agent_id = generate_instance_uid_string()
      error = build_server_error_response(:ServerErrorResponseType_BadRequest, "Invalid message")

      result = Encoder.build_server_to_agent(agent_id, error_response: error)

      assert result.error_response == error
    end

    test "builds ServerToAgent with all options" do
      agent_id = generate_instance_uid_string()
      remote_config = build_agent_remote_config()

      result =
        Encoder.build_server_to_agent(agent_id,
          capabilities: 63,
          remote_config: remote_config,
          flags: 3
        )

      assert result.capabilities == 63
      assert result.remote_config == remote_config
      assert result.flags == 3
    end
  end

  describe "build_error_response/1" do
    test "builds error response for :unmatched_topic" do
      result = Encoder.build_error_response(:unmatched_topic)

      assert %Opamp.Proto.ServerToAgent{} = result
      assert result.error_response != nil
      assert result.error_response.type == :ServerErrorResponseType_Unavailable
      assert result.error_response.error_message == "Connection idled, reconnect requested"
    end

    test "builds error response for {:unavailable, message}" do
      result = Encoder.build_error_response({:unavailable, "Server is down"})

      assert result.error_response.type == :ServerErrorResponseType_Unavailable
      assert result.error_response.error_message == "Server is down"
    end

    test "builds error response for {:bad_request, message}" do
      result = Encoder.build_error_response({:bad_request, "Invalid payload"})

      assert result.error_response.type == :ServerErrorResponseType_BadRequest
      assert result.error_response.error_message == "Invalid payload"
    end

    test "builds error response for string reason" do
      result = Encoder.build_error_response("Something went wrong")

      assert result.error_response.type == :ServerErrorResponseType_Unavailable
      assert result.error_response.error_message == "Something went wrong"
    end

    test "error responses have minimal fields set" do
      result = Encoder.build_error_response(:unmatched_topic)

      # Protobuf defaults: empty binary for bytes, 0 for integers
      assert result.instance_uid == "" || result.instance_uid == nil
      assert result.remote_config == nil
      assert result.capabilities == 0
    end
  end

  describe "encode/1" do
    test "encodes ServerToAgent to binary" do
      server_to_agent = build_server_to_agent()

      result = Encoder.encode(server_to_agent)

      assert is_binary(result)
      # Verify it can be decoded back
      decoded = Opamp.Proto.ServerToAgent.decode(result)
      assert decoded.capabilities == server_to_agent.capabilities
    end

    test "encodes minimal ServerToAgent" do
      server_to_agent = %Opamp.Proto.ServerToAgent{
        instance_uid: "test-id",
        capabilities: 1
      }

      result = Encoder.encode(server_to_agent)

      assert is_binary(result)
      decoded = Opamp.Proto.ServerToAgent.decode(result)
      assert decoded.instance_uid == "test-id"
    end

    test "encodes ServerToAgent with remote config" do
      remote_config = build_agent_remote_config()
      server_to_agent = build_server_to_agent(%{remote_config: remote_config})

      result = Encoder.encode(server_to_agent)

      decoded = Opamp.Proto.ServerToAgent.decode(result)
      assert decoded.remote_config != nil
      assert decoded.remote_config.config != nil
    end

    test "encodes ServerToAgent with error response" do
      error = %Opamp.Proto.ServerErrorResponse{
        type: :ServerErrorResponseType_Unavailable,
        error_message: "Test error"
      }

      server_to_agent = build_server_to_agent(%{error_response: error})

      result = Encoder.encode(server_to_agent)

      decoded = Opamp.Proto.ServerToAgent.decode(result)
      assert decoded.error_response.error_message == "Test error"
    end

    test "encodes ServerToAgent with connection settings" do
      settings =
        build_connection_settings_offers(%{
          opamp: build_opamp_connection_settings()
        })

      server_to_agent = build_server_to_agent(%{connection_settings: settings})

      result = Encoder.encode(server_to_agent)

      decoded = Opamp.Proto.ServerToAgent.decode(result)
      assert decoded.connection_settings != nil
      assert decoded.connection_settings.opamp != nil
    end

    test "encodes ServerToAgent with packages available" do
      packages = build_packages_available()
      server_to_agent = build_server_to_agent(%{packages_available: packages})

      result = Encoder.encode(server_to_agent)

      decoded = Opamp.Proto.ServerToAgent.decode(result)
      assert decoded.packages_available != nil
      assert map_size(decoded.packages_available.packages) == 1
    end

    test "encodes ServerToAgent with command" do
      command = %Opamp.Proto.ServerToAgentCommand{type: :CommandType_Restart}
      server_to_agent = build_server_to_agent(%{command: command})

      result = Encoder.encode(server_to_agent)

      decoded = Opamp.Proto.ServerToAgent.decode(result)
      assert decoded.command.type == :CommandType_Restart
    end

    test "encodes ServerToAgent with agent identification" do
      new_uid = generate_instance_uid()
      identification = %Opamp.Proto.AgentIdentification{new_instance_uid: new_uid}
      server_to_agent = build_server_to_agent(%{agent_identification: identification})

      result = Encoder.encode(server_to_agent)

      decoded = Opamp.Proto.ServerToAgent.decode(result)
      assert decoded.agent_identification.new_instance_uid == new_uid
    end

    test "encodes ServerToAgent with custom capabilities" do
      custom_caps = %Opamp.Proto.CustomCapabilities{
        capabilities: ["custom:feature1", "custom:feature2"]
      }

      server_to_agent = build_server_to_agent(%{custom_capabilities: custom_caps})

      result = Encoder.encode(server_to_agent)

      decoded = Opamp.Proto.ServerToAgent.decode(result)
      assert decoded.custom_capabilities.capabilities == ["custom:feature1", "custom:feature2"]
    end

    test "encodes ServerToAgent with custom message" do
      custom_msg = %Opamp.Proto.CustomMessage{
        capability: "custom:feature1",
        type: "request",
        data: "some data"
      }

      server_to_agent = build_server_to_agent(%{custom_message: custom_msg})

      result = Encoder.encode(server_to_agent)

      decoded = Opamp.Proto.ServerToAgent.decode(result)
      assert decoded.custom_message.capability == "custom:feature1"
      assert decoded.custom_message.data == "some data"
    end
  end

  describe "encode_config_map/1" do
    test "encodes AgentConfigMap to binary" do
      config_map = build_agent_config_map()

      result = Encoder.encode_config_map(config_map)

      assert is_binary(result)
      decoded = Opamp.Proto.AgentConfigMap.decode(result)
      assert map_size(decoded.config_map) == 2
    end

    test "encodes empty config map" do
      config_map = %Opamp.Proto.AgentConfigMap{config_map: %{}}

      result = Encoder.encode_config_map(config_map)

      assert is_binary(result)
      decoded = Opamp.Proto.AgentConfigMap.decode(result)
      assert decoded.config_map == %{}
    end

    test "encodes config map with large config file" do
      large_body = String.duplicate("x", 100_000)

      config_map =
        build_agent_config_map(%{
          "large.yaml" => build_agent_config_file(large_body)
        })

      result = Encoder.encode_config_map(config_map)

      decoded = Opamp.Proto.AgentConfigMap.decode(result)
      assert byte_size(decoded.config_map["large.yaml"].body) == 100_000
    end
  end

  describe "round-trip encoding" do
    test "ServerToAgent survives encode/decode round trip" do
      original =
        build_server_to_agent(%{
          flags: 3,
          remote_config: build_agent_remote_config()
        })

      encoded = Encoder.encode(original)
      decoded = Opamp.Proto.ServerToAgent.decode(encoded)

      assert decoded.capabilities == original.capabilities
      assert decoded.flags == original.flags
      assert decoded.remote_config.config_hash == original.remote_config.config_hash
    end

    test "complex ServerToAgent survives round trip" do
      original =
        build_server_to_agent(%{
          flags: 1,
          remote_config: build_agent_remote_config(),
          connection_settings:
            build_connection_settings_offers(%{
              opamp:
                build_opamp_connection_settings(%{
                  tls: build_tls_connection_settings()
                })
            }),
          packages_available: build_packages_available()
        })

      encoded = Encoder.encode(original)
      decoded = Opamp.Proto.ServerToAgent.decode(encoded)

      assert decoded.connection_settings.opamp.tls != nil
      assert decoded.packages_available != nil
    end
  end
end
