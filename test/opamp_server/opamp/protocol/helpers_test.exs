defmodule OpAMPServer.OpAMP.Protocol.HelpersTest do
  use ExUnit.Case, async: true
  use OpAMPServer.OpAMPCase

  alias OpAMPServer.OpAMP.Protocol.Helpers

  describe "server_capabilities/0" do
    test "returns a non-zero bitmask" do
      result = Helpers.server_capabilities()

      assert is_integer(result)
      assert result > 0
    end

    test "includes AcceptsStatus capability" do
      import Bitwise
      result = Helpers.server_capabilities()

      assert (result &&& 1) != 0
    end

    test "includes OffersRemoteConfig capability" do
      import Bitwise
      result = Helpers.server_capabilities()

      assert (result &&& 2) != 0
    end

    test "includes AcceptsEffectiveConfig capability" do
      import Bitwise
      result = Helpers.server_capabilities()

      assert (result &&& 4) != 0
    end

    test "includes OffersConnectionSettings capability" do
      import Bitwise
      result = Helpers.server_capabilities()

      assert (result &&& 32) != 0
    end

    test "includes AcceptsConnectionSettingsRequest capability" do
      import Bitwise
      result = Helpers.server_capabilities()

      assert (result &&& 64) != 0
    end

    test "returns consistent value across calls" do
      result1 = Helpers.server_capabilities()
      result2 = Helpers.server_capabilities()

      assert result1 == result2
    end
  end

  describe "server_capability_to_int/1" do
    test "converts Unspecified to 0" do
      result =
        Helpers.server_capability_to_int(
          Opamp.Proto.ServerCapabilities.ServerCapabilities_Unspecified
        )

      assert result == 0
    end

    test "converts AcceptsStatus to 1" do
      result =
        Helpers.server_capability_to_int(
          Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsStatus
        )

      assert result == 1
    end

    test "converts OffersRemoteConfig to 2" do
      result =
        Helpers.server_capability_to_int(
          Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersRemoteConfig
        )

      assert result == 2
    end

    test "converts AcceptsEffectiveConfig to 4" do
      result =
        Helpers.server_capability_to_int(
          Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsEffectiveConfig
        )

      assert result == 4
    end

    test "converts OffersPackages to 8" do
      result =
        Helpers.server_capability_to_int(
          Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersPackages
        )

      assert result == 8
    end

    test "converts AcceptsPackagesStatus to 16" do
      result =
        Helpers.server_capability_to_int(
          Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsPackagesStatus
        )

      assert result == 16
    end

    test "converts OffersConnectionSettings to 32" do
      result =
        Helpers.server_capability_to_int(
          Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersConnectionSettings
        )

      assert result == 32
    end

    test "converts AcceptsConnectionSettingsRequest to 64" do
      result =
        Helpers.server_capability_to_int(
          Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsConnectionSettingsRequest
        )

      assert result == 64
    end

    test "returns 0 for unknown capability" do
      result = Helpers.server_capability_to_int(:unknown)
      assert result == 0
    end
  end

  describe "agent_capability_to_int/1" do
    test "converts all standard capabilities correctly" do
      capabilities = [
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_Unspecified, 0},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus, 1},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsRemoteConfig, 2},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsEffectiveConfig, 4},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsPackages, 8},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsPackageStatuses, 16},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsOwnTraces, 32},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsOwnMetrics, 64},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsOwnLogs, 128},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsOpAMPConnectionSettings, 256},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsOtherConnectionSettings, 512},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsRestartCommand, 1024},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHealth, 2048},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsRemoteConfig, 4096},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHeartbeat, 8192},
        {Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsAvailableComponents, 16384}
      ]

      for {cap, expected} <- capabilities do
        assert Helpers.agent_capability_to_int(cap) == expected,
               "Expected #{inspect(cap)} to be #{expected}"
      end
    end

    test "returns 0 for unknown capability" do
      assert Helpers.agent_capability_to_int(:unknown) == 0
    end
  end

  describe "agent_has_capability?/2" do
    test "returns true when agent has the capability" do
      import Bitwise
      # ReportsStatus, AcceptsRemoteConfig, ReportsEffectiveConfig
      agent = %{capabilities: 1 ||| 2 ||| 4}

      assert Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus
             )

      assert Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsRemoteConfig
             )

      assert Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsEffectiveConfig
             )
    end

    test "returns false when agent lacks the capability" do
      # Only ReportsStatus
      agent = %{capabilities: 1}

      refute Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsRemoteConfig
             )

      refute Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHealth
             )
    end

    test "returns false when capabilities is nil" do
      agent = %{capabilities: nil}

      refute Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus
             )
    end

    test "returns false when capabilities is not an integer" do
      agent = %{capabilities: "invalid"}

      refute Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus
             )
    end

    test "returns false when capabilities key is missing" do
      agent = %{}

      refute Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus
             )
    end

    test "works with all capabilities set" do
      agent = %{capabilities: all_agent_capabilities()}

      # Check a few capabilities
      assert Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus
             )

      assert Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHealth
             )

      assert Helpers.agent_has_capability?(
               agent,
               Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsAvailableComponents
             )
    end
  end

  describe "server_flags_to_int/1" do
    test "converts list of flags to bitmask" do
      flags = [
        Opamp.Proto.ServerToAgentFlags.ServerToAgentFlags_ReportFullState,
        Opamp.Proto.ServerToAgentFlags.ServerToAgentFlags_ReportAvailableComponents
      ]

      result = Helpers.server_flags_to_int(flags)

      # 1 | 2
      assert result == 3
    end

    test "converts single flag to int" do
      result =
        Helpers.server_flags_to_int(
          Opamp.Proto.ServerToAgentFlags.ServerToAgentFlags_ReportFullState
        )

      assert result == 1
    end

    test "converts ReportAvailableComponents to 2" do
      result =
        Helpers.server_flags_to_int(
          Opamp.Proto.ServerToAgentFlags.ServerToAgentFlags_ReportAvailableComponents
        )

      assert result == 2
    end

    test "converts empty list to 0" do
      result = Helpers.server_flags_to_int([])
      assert result == 0
    end

    test "converts Unspecified to 0" do
      result =
        Helpers.server_flags_to_int(Opamp.Proto.ServerToAgentFlags.ServerToAgentFlags_Unspecified)

      assert result == 0
    end
  end

  describe "attributes_to_map/2" do
    test "converts KeyValue list to map" do
      attributes = [
        build_key_value("key1", "value1"),
        build_key_value("key2", "value2")
      ]

      result = Helpers.attributes_to_map(attributes)

      assert result == %{"key1" => "value1", "key2" => "value2"}
    end

    test "handles empty list" do
      result = Helpers.attributes_to_map([])
      assert result == %{}
    end

    test "handles integer values" do
      attributes = [build_key_value_int("count", 42)]

      result = Helpers.attributes_to_map(attributes)

      assert result == %{"count" => 42}
    end

    test "handles boolean values" do
      attributes = [build_key_value_bool("enabled", true)]

      result = Helpers.attributes_to_map(attributes)

      assert result == %{"enabled" => true}
    end

    test "handles double values" do
      attributes = [build_key_value_double("ratio", 3.14)]

      result = Helpers.attributes_to_map(attributes)

      assert result == %{"ratio" => 3.14}
    end

    test "handles array values" do
      attributes = [build_key_value_array("tags", ["a", "b", "c"])]

      result = Helpers.attributes_to_map(attributes)

      assert result == %{"tags" => ["a", "b", "c"]}
    end

    test "handles nested map values" do
      attributes = [build_key_value_map("metadata", %{foo: "bar", baz: "qux"})]

      result = Helpers.attributes_to_map(attributes)

      assert result["metadata"]["foo"] == "bar"
      assert result["metadata"]["baz"] == "qux"
    end

    test "casts values to strings with cast_string option" do
      attributes = [
        build_key_value_int("count", 42),
        build_key_value_bool("enabled", true),
        build_key_value_double("ratio", 3.14)
      ]

      result = Helpers.attributes_to_map(attributes, cast_string: true)

      assert result["count"] == "42"
      assert result["enabled"] == "true"
      assert result["ratio"] == "3.14"
    end

    test "handles mixed value types" do
      attributes = [
        build_key_value("name", "test"),
        build_key_value_int("count", 10),
        build_key_value_bool("active", false),
        build_key_value_array("items", [1, 2, 3])
      ]

      result = Helpers.attributes_to_map(attributes)

      assert result == %{
               "name" => "test",
               "count" => 10,
               "active" => false,
               "items" => [1, 2, 3]
             }
    end
  end

  describe "clean_any_value/2" do
    test "returns nil for nil input" do
      assert Helpers.clean_any_value(nil, []) == nil
    end

    test "returns nil for AnyValue with nil value" do
      any_value = %Opamp.Proto.AnyValue{value: nil}
      assert Helpers.clean_any_value(any_value, []) == nil
    end

    test "extracts string value" do
      any_value = build_any_value("hello")
      assert Helpers.clean_any_value(any_value, []) == "hello"
    end

    test "extracts integer value" do
      any_value = build_any_value(42)
      assert Helpers.clean_any_value(any_value, []) == 42
    end

    test "extracts boolean value" do
      any_value = build_any_value(true)
      assert Helpers.clean_any_value(any_value, []) == true
    end

    test "extracts double value" do
      any_value = build_any_value(3.14159)
      assert Helpers.clean_any_value(any_value, []) == 3.14159
    end

    test "extracts bytes value" do
      any_value = %Opamp.Proto.AnyValue{value: {:bytes_value, <<1, 2, 3>>}}
      assert Helpers.clean_any_value(any_value, []) == <<1, 2, 3>>
    end

    test "extracts array value" do
      values = [
        %Opamp.Proto.AnyValue{value: {:string_value, "a"}},
        %Opamp.Proto.AnyValue{value: {:string_value, "b"}}
      ]

      any_value = %Opamp.Proto.AnyValue{
        value: {:array_value, %Opamp.Proto.ArrayValue{values: values}}
      }

      assert Helpers.clean_any_value(any_value, []) == ["a", "b"]
    end

    test "extracts nested kvlist value" do
      kv_list = [
        build_key_value("inner1", "val1"),
        build_key_value("inner2", "val2")
      ]

      any_value = %Opamp.Proto.AnyValue{
        value: {:kvlist_value, %Opamp.Proto.KeyValueList{values: kv_list}}
      }

      result = Helpers.clean_any_value(any_value, [])

      assert result == %{"inner1" => "val1", "inner2" => "val2"}
    end

    test "casts integer to string with option" do
      any_value = build_any_value(42)
      assert Helpers.clean_any_value(any_value, cast_string: true) == "42"
    end

    test "casts boolean to string with option" do
      any_value = build_any_value(false)
      assert Helpers.clean_any_value(any_value, cast_string: true) == "false"
    end

    test "casts double to string with option" do
      any_value = build_any_value(2.5)
      assert Helpers.clean_any_value(any_value, cast_string: true) == "2.5"
    end

    test "does not cast string values" do
      any_value = build_any_value("already string")
      assert Helpers.clean_any_value(any_value, cast_string: true) == "already string"
    end

    test "recursively applies cast_string to arrays" do
      values = [
        %Opamp.Proto.AnyValue{value: {:int_value, 1}},
        %Opamp.Proto.AnyValue{value: {:int_value, 2}}
      ]

      any_value = %Opamp.Proto.AnyValue{
        value: {:array_value, %Opamp.Proto.ArrayValue{values: values}}
      }

      result = Helpers.clean_any_value(any_value, cast_string: true)

      assert result == ["1", "2"]
    end
  end

  describe "config_hash/1" do
    test "generates MD5 hash of config map" do
      config_map = build_agent_config_map()

      result = Helpers.config_hash(config_map)

      assert is_binary(result)
      # MD5 produces 16 bytes
      assert byte_size(result) == 16
    end

    test "same config produces same hash" do
      config_map =
        build_agent_config_map(%{
          "test.yaml" => build_agent_config_file("content")
        })

      hash1 = Helpers.config_hash(config_map)
      hash2 = Helpers.config_hash(config_map)

      assert hash1 == hash2
    end

    test "different configs produce different hashes" do
      config1 =
        build_agent_config_map(%{
          "test.yaml" => build_agent_config_file("content1")
        })

      config2 =
        build_agent_config_map(%{
          "test.yaml" => build_agent_config_file("content2")
        })

      hash1 = Helpers.config_hash(config1)
      hash2 = Helpers.config_hash(config2)

      assert hash1 != hash2
    end

    test "empty config map produces valid hash" do
      config_map = %Opamp.Proto.AgentConfigMap{config_map: %{}}

      result = Helpers.config_hash(config_map)

      assert is_binary(result)
      assert byte_size(result) == 16
    end
  end
end
