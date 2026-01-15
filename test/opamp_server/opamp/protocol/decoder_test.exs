defmodule OpAMPServer.OpAMP.Protocol.DecoderTest do
  use ExUnit.Case, async: true
  use OpAMPServer.OpAMPCase

  alias OpAMPServer.OpAMP.Protocol.Decoder

  describe "decode_agent_message/1" do
    test "decodes a minimal AgentToServer message with header" do
      instance_uid = generate_instance_uid()
      message = build_agent_to_server(%{instance_uid: instance_uid, sequence_num: 42})
      binary = encode_with_header(message)

      assert {:ok, proto, agent_id} = Decoder.decode_agent_message(binary)
      assert proto.sequence_num == 42
      assert proto.instance_uid == instance_uid
      assert is_binary(agent_id)
      # UUID string format
      assert String.length(agent_id) == 36
    end

    test "decodes AgentToServer with agent description" do
      message = build_agent_to_server_with_description()
      binary = encode_with_header(message)

      assert {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)
      assert proto.agent_description != nil
      assert length(proto.agent_description.identifying_attributes) == 2
      assert length(proto.agent_description.non_identifying_attributes) == 2
    end

    test "decodes AgentToServer with health information" do
      message =
        build_agent_to_server_with_health(%{
          health: build_component_health(%{healthy: true, status: "Running"})
        })

      binary = encode_with_header(message)

      assert {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)
      assert proto.health != nil
      assert proto.health.healthy == true
      assert proto.health.status == "Running"
    end

    test "decodes AgentToServer with nested component health" do
      message =
        build_agent_to_server_with_health(%{
          health: build_component_health_with_children()
        })

      binary = encode_with_header(message)

      assert {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)
      assert proto.health != nil
      assert map_size(proto.health.component_health_map) == 3
      assert proto.health.component_health_map["exporter/otlp"].healthy == false
    end

    test "decodes AgentToServer with effective config" do
      config =
        build_effective_config(%{
          config_map:
            build_agent_config_map(%{
              "test.yaml" => build_agent_config_file("key: value")
            })
        })

      message = build_agent_to_server_with_config(%{effective_config: config})
      binary = encode_with_header(message)

      assert {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)
      assert proto.effective_config != nil
      assert proto.effective_config.config_map != nil
      assert map_size(proto.effective_config.config_map.config_map) == 1
    end

    test "decodes AgentToServer with remote config status" do
      status =
        build_remote_config_status(%{
          status: :RemoteConfigStatuses_APPLYING,
          error_message: ""
        })

      message = build_agent_to_server(%{remote_config_status: status})
      binary = encode_with_header(message)

      assert {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)
      assert proto.remote_config_status != nil
      assert proto.remote_config_status.status == :RemoteConfigStatuses_APPLYING
    end

    test "decodes AgentToServer with capabilities" do
      capabilities = all_agent_capabilities()
      message = build_agent_to_server(%{capabilities: capabilities})
      binary = encode_with_header(message)

      assert {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)
      assert proto.capabilities == capabilities
    end

    test "decodes full AgentToServer message" do
      message = build_full_agent_to_server()
      binary = encode_with_header(message)

      assert {:ok, proto, agent_id} = Decoder.decode_agent_message(binary)
      assert is_binary(agent_id)
      assert proto.agent_description != nil
      assert proto.health != nil
      assert proto.effective_config != nil
      assert proto.remote_config_status != nil
    end

    test "decodes AgentToServer with available components" do
      components = build_available_components()
      message = build_agent_to_server(%{available_components: components})
      binary = encode_with_header(message)

      assert {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)
      assert proto.available_components != nil
      assert map_size(proto.available_components.components) == 2
    end

    test "decodes AgentToServer with flags" do
      message = build_agent_to_server(%{flags: 1})
      binary = encode_with_header(message)

      assert {:ok, proto, _agent_id} = Decoder.decode_agent_message(binary)
      assert proto.flags == 1
    end

    test "returns error for invalid binary" do
      assert {:error, :invalid_message_format} = Decoder.decode_agent_message(<<>>)
      # Strings are binaries in Elixir, so they get decoded (and fail as invalid protobuf)
      assert {:error, {:decode_error, _}} = Decoder.decode_agent_message("not binary")
    end

    test "returns error for malformed protobuf data" do
      # Header byte followed by invalid protobuf
      invalid_binary = <<0, 255, 255, 255, 255, 255>>

      assert {:error, {:decode_error, _}} = Decoder.decode_agent_message(invalid_binary)
    end

    test "handles different header byte values" do
      message = build_agent_to_server()
      # OpAMP allows different header values
      binary_with_header_1 = <<1>> <> Opamp.Proto.AgentToServer.encode(message)

      assert {:ok, _proto, _agent_id} = Decoder.decode_agent_message(binary_with_header_1)
    end
  end

  describe "decode_raw/1" do
    test "decodes raw protobuf without header" do
      message = build_agent_to_server(%{sequence_num: 99})
      raw_binary = Opamp.Proto.AgentToServer.encode(message)

      assert {:ok, proto} = Decoder.decode_raw(raw_binary)
      assert proto.sequence_num == 99
    end

    test "returns error for invalid protobuf" do
      assert {:error, {:decode_error, _}} = Decoder.decode_raw(<<255, 255, 255>>)
    end

    test "decodes empty AgentToServer" do
      empty = %Opamp.Proto.AgentToServer{}
      raw_binary = Opamp.Proto.AgentToServer.encode(empty)

      assert {:ok, proto} = Decoder.decode_raw(raw_binary)
      assert proto.sequence_num == 0
      assert proto.instance_uid == <<>>
    end
  end

  describe "UUID handling" do
    test "correctly converts binary UUID to string format" do
      # Known UUID for testing
      uuid_string = "550e8400-e29b-41d4-a716-446655440000"
      {:ok, uuid_binary} = Ecto.UUID.dump(uuid_string)

      message = build_agent_to_server(%{instance_uid: uuid_binary})
      binary = encode_with_header(message)

      assert {:ok, _proto, agent_id} = Decoder.decode_agent_message(binary)
      assert agent_id == uuid_string
    end

    test "handles multiple messages with different UUIDs" do
      uuids = for _ <- 1..10, do: generate_instance_uid()

      results =
        Enum.map(uuids, fn uid ->
          message = build_agent_to_server(%{instance_uid: uid})
          binary = encode_with_header(message)
          {:ok, _proto, agent_id} = Decoder.decode_agent_message(binary)
          agent_id
        end)

      # All should be unique
      assert length(Enum.uniq(results)) == 10
    end
  end

  describe "sequence number handling" do
    test "handles sequence number 0" do
      message = build_agent_to_server(%{sequence_num: 0})
      binary = encode_with_header(message)

      assert {:ok, proto, _} = Decoder.decode_agent_message(binary)
      assert proto.sequence_num == 0
    end

    test "handles large sequence numbers" do
      message = build_agent_to_server(%{sequence_num: 18_446_744_073_709_551_615})
      binary = encode_with_header(message)

      assert {:ok, proto, _} = Decoder.decode_agent_message(binary)
      assert proto.sequence_num == 18_446_744_073_709_551_615
    end
  end
end
