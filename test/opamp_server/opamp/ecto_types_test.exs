defmodule OpAMPServer.OpAMP.EctoTypesTest do
  use ExUnit.Case, async: true
  use OpAMPServer.OpAMPCase

  alias OpAMPServer.OpAMP.EctoTypes

  describe "AgentDescription" do
    test "type/0 returns :binary" do
      assert EctoTypes.AgentDescription.type() == :binary
    end

    test "cast/1 accepts any term" do
      description = build_agent_description()
      assert {:ok, ^description} = EctoTypes.AgentDescription.cast(description)
    end

    test "cast/1 accepts nil" do
      assert {:ok, nil} = EctoTypes.AgentDescription.cast(nil)
    end

    test "dump/1 encodes AgentDescription to binary" do
      description = build_agent_description()

      assert {:ok, binary} = EctoTypes.AgentDescription.dump(description)
      assert is_binary(binary)
    end

    test "dump/1 returns nil for nil" do
      assert {:ok, nil} = EctoTypes.AgentDescription.dump(nil)
    end

    test "dump/1 returns error for invalid type" do
      assert :error = EctoTypes.AgentDescription.dump("invalid")
      assert :error = EctoTypes.AgentDescription.dump(%{})
    end

    test "load/1 decodes binary to AgentDescription" do
      description = build_agent_description()
      binary = Opamp.Proto.AgentDescription.encode(description)

      assert {:ok, loaded} = EctoTypes.AgentDescription.load(binary)
      assert %Opamp.Proto.AgentDescription{} = loaded
      assert length(loaded.identifying_attributes) == 2
    end

    test "load/1 returns nil for nil" do
      assert {:ok, nil} = EctoTypes.AgentDescription.load(nil)
    end

    test "round trip dump/load preserves data" do
      description =
        build_agent_description(%{
          identifying_attributes: [
            build_key_value("service.name", "my-service"),
            build_key_value("service.namespace", "production")
          ],
          non_identifying_attributes: [
            build_key_value("host.arch", "amd64")
          ]
        })

      {:ok, binary} = EctoTypes.AgentDescription.dump(description)
      {:ok, loaded} = EctoTypes.AgentDescription.load(binary)

      assert length(loaded.identifying_attributes) == 2
      assert length(loaded.non_identifying_attributes) == 1
    end
  end

  describe "ComponentHealth" do
    test "type/0 returns :binary" do
      assert EctoTypes.ComponentHealth.type() == :binary
    end

    test "cast/1 accepts ComponentHealth struct" do
      health = build_component_health()
      assert {:ok, ^health} = EctoTypes.ComponentHealth.cast(health)
    end

    test "dump/1 encodes ComponentHealth to binary" do
      health = build_component_health(%{healthy: true, status: "Running"})

      assert {:ok, binary} = EctoTypes.ComponentHealth.dump(health)
      assert is_binary(binary)
    end

    test "dump/1 returns nil for nil" do
      assert {:ok, nil} = EctoTypes.ComponentHealth.dump(nil)
    end

    test "dump/1 returns error for invalid type" do
      assert :error = EctoTypes.ComponentHealth.dump("invalid")
    end

    test "load/1 decodes binary to ComponentHealth" do
      health = build_component_health(%{healthy: false, last_error: "Connection failed"})
      binary = Opamp.Proto.ComponentHealth.encode(health)

      assert {:ok, loaded} = EctoTypes.ComponentHealth.load(binary)
      assert loaded.healthy == false
      assert loaded.last_error == "Connection failed"
    end

    test "load/1 returns nil for empty string" do
      assert {:ok, nil} = EctoTypes.ComponentHealth.load("")
    end

    test "load/1 returns nil for nil" do
      assert {:ok, nil} = EctoTypes.ComponentHealth.load(nil)
    end

    test "round trip preserves nested component health map" do
      health = build_component_health_with_children()

      {:ok, binary} = EctoTypes.ComponentHealth.dump(health)
      {:ok, loaded} = EctoTypes.ComponentHealth.load(binary)

      assert map_size(loaded.component_health_map) == 3
      assert loaded.component_health_map["exporter/otlp"].healthy == false
    end
  end

  describe "EffectiveConfig" do
    test "type/0 returns :binary" do
      assert EctoTypes.EffectiveConfig.type() == :binary
    end

    test "cast/1 accepts EffectiveConfig struct" do
      config = build_effective_config()
      assert {:ok, ^config} = EctoTypes.EffectiveConfig.cast(config)
    end

    test "dump/1 encodes EffectiveConfig to binary" do
      config = build_effective_config()

      assert {:ok, binary} = EctoTypes.EffectiveConfig.dump(config)
      assert is_binary(binary)
    end

    test "dump/1 returns nil for nil" do
      assert {:ok, nil} = EctoTypes.EffectiveConfig.dump(nil)
    end

    test "dump/1 returns error for invalid type" do
      assert :error = EctoTypes.EffectiveConfig.dump(%{})
    end

    test "load/1 decodes binary to EffectiveConfig" do
      config =
        build_effective_config(%{
          config_map:
            build_agent_config_map(%{
              "test.yaml" => build_agent_config_file("key: value")
            })
        })

      binary = Opamp.Proto.EffectiveConfig.encode(config)

      assert {:ok, loaded} = EctoTypes.EffectiveConfig.load(binary)
      assert loaded.config_map != nil
      assert map_size(loaded.config_map.config_map) == 1
    end

    test "load/1 returns nil for nil" do
      assert {:ok, nil} = EctoTypes.EffectiveConfig.load(nil)
    end

    test "round trip preserves config file content" do
      yaml_content = """
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
      """

      config =
        build_effective_config(%{
          config_map:
            build_agent_config_map(%{
              "collector.yaml" => build_agent_config_file(yaml_content)
            })
        })

      {:ok, binary} = EctoTypes.EffectiveConfig.dump(config)
      {:ok, loaded} = EctoTypes.EffectiveConfig.load(binary)

      assert loaded.config_map.config_map["collector.yaml"].body == yaml_content
    end
  end

  describe "RemoteConfigStatus" do
    test "type/0 returns :binary" do
      assert EctoTypes.RemoteConfigStatus.type() == :binary
    end

    test "cast/1 accepts RemoteConfigStatus struct" do
      status = build_remote_config_status()
      assert {:ok, ^status} = EctoTypes.RemoteConfigStatus.cast(status)
    end

    test "dump/1 encodes RemoteConfigStatus to binary" do
      status =
        build_remote_config_status(%{
          status: :RemoteConfigStatuses_APPLIED
        })

      assert {:ok, binary} = EctoTypes.RemoteConfigStatus.dump(status)
      assert is_binary(binary)
    end

    test "dump/1 returns nil for nil" do
      assert {:ok, nil} = EctoTypes.RemoteConfigStatus.dump(nil)
    end

    test "dump/1 returns error for invalid type" do
      assert :error = EctoTypes.RemoteConfigStatus.dump("invalid")
    end

    test "load/1 decodes binary to RemoteConfigStatus" do
      status =
        build_remote_config_status(%{
          status: :RemoteConfigStatuses_FAILED,
          error_message: "Invalid YAML"
        })

      binary = Opamp.Proto.RemoteConfigStatus.encode(status)

      assert {:ok, loaded} = EctoTypes.RemoteConfigStatus.load(binary)
      assert loaded.status == :RemoteConfigStatuses_FAILED
      assert loaded.error_message == "Invalid YAML"
    end

    test "load/1 returns nil for nil" do
      assert {:ok, nil} = EctoTypes.RemoteConfigStatus.load(nil)
    end

    test "round trip preserves all status values" do
      statuses = [
        :RemoteConfigStatuses_UNSET,
        :RemoteConfigStatuses_APPLIED,
        :RemoteConfigStatuses_APPLYING,
        :RemoteConfigStatuses_FAILED
      ]

      for status_enum <- statuses do
        status = build_remote_config_status(%{status: status_enum})
        {:ok, binary} = EctoTypes.RemoteConfigStatus.dump(status)
        {:ok, loaded} = EctoTypes.RemoteConfigStatus.load(binary)

        assert loaded.status == status_enum
      end
    end

    test "round trip preserves config hash" do
      hash = :crypto.hash(:md5, "test-config-content")
      status = build_remote_config_status(%{last_remote_config_hash: hash})

      {:ok, binary} = EctoTypes.RemoteConfigStatus.dump(status)
      {:ok, loaded} = EctoTypes.RemoteConfigStatus.load(binary)

      assert loaded.last_remote_config_hash == hash
    end
  end

  describe "AgentRemoteConfig" do
    test "type/0 returns :binary" do
      assert EctoTypes.AgentRemoteConfig.type() == :binary
    end

    test "cast/1 accepts AgentRemoteConfig struct" do
      config = build_agent_remote_config()
      assert {:ok, ^config} = EctoTypes.AgentRemoteConfig.cast(config)
    end

    test "dump/1 encodes AgentRemoteConfig to binary" do
      config = build_agent_remote_config()

      assert {:ok, binary} = EctoTypes.AgentRemoteConfig.dump(config)
      assert is_binary(binary)
    end

    test "dump/1 returns nil for nil" do
      assert {:ok, nil} = EctoTypes.AgentRemoteConfig.dump(nil)
    end

    test "dump/1 returns error for invalid type" do
      assert :error = EctoTypes.AgentRemoteConfig.dump(%{})
    end

    test "load/1 decodes binary to AgentRemoteConfig" do
      config = build_agent_remote_config()
      binary = Opamp.Proto.AgentRemoteConfig.encode(config)

      assert {:ok, loaded} = EctoTypes.AgentRemoteConfig.load(binary)
      assert %Opamp.Proto.AgentRemoteConfig{} = loaded
      assert loaded.config != nil
      assert loaded.config_hash != nil
    end

    test "load/1 returns nil for nil" do
      assert {:ok, nil} = EctoTypes.AgentRemoteConfig.load(nil)
    end

    test "round trip preserves config and hash" do
      config_map =
        build_agent_config_map(%{
          "receiver.yaml" => build_agent_config_file("otlp:\n  endpoint: localhost:4317"),
          "exporter.yaml" => build_agent_config_file("otlp:\n  endpoint: localhost:4318")
        })

      config = %Opamp.Proto.AgentRemoteConfig{
        config: config_map,
        config_hash: :crypto.hash(:md5, Opamp.Proto.AgentConfigMap.encode(config_map))
      }

      {:ok, binary} = EctoTypes.AgentRemoteConfig.dump(config)
      {:ok, loaded} = EctoTypes.AgentRemoteConfig.load(binary)

      assert map_size(loaded.config.config_map) == 2
      assert loaded.config_hash == config.config_hash
    end
  end

  describe "binary size and encoding" do
    test "AgentDescription encoding produces reasonable size" do
      description = build_agent_description()
      {:ok, binary} = EctoTypes.AgentDescription.dump(description)

      # Should be reasonably compact
      assert byte_size(binary) < 1000
    end

    test "ComponentHealth with large component map" do
      children =
        for i <- 1..100, into: %{} do
          {"component_#{i}", build_component_health(%{status: "Running"})}
        end

      health = build_component_health(%{component_health_map: children})

      {:ok, binary} = EctoTypes.ComponentHealth.dump(health)
      {:ok, loaded} = EctoTypes.ComponentHealth.load(binary)

      assert map_size(loaded.component_health_map) == 100
    end

    test "EffectiveConfig with large config file" do
      large_config = String.duplicate("key: value\n", 10000)

      config =
        build_effective_config(%{
          config_map:
            build_agent_config_map(%{
              "large.yaml" => build_agent_config_file(large_config)
            })
        })

      {:ok, binary} = EctoTypes.EffectiveConfig.dump(config)
      {:ok, loaded} = EctoTypes.EffectiveConfig.load(binary)

      assert byte_size(loaded.config_map.config_map["large.yaml"].body) == byte_size(large_config)
    end
  end
end
