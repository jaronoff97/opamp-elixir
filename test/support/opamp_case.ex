defmodule OpAMPServer.OpAMPCase do
  @moduledoc """
  Test case template for OpAMP protocol tests.

  Provides helpers and factory functions for creating proto messages.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import OpAMPServer.OpAMPCase
      alias OpAMPServer.OpAMP.Protocol
      alias OpAMPServer.OpAMP.Protocol.{Decoder, Encoder, Helpers}
      alias OpAMPServer.OpAMP.ConnectionManager
    end
  end

  @doc """
  Generate a random UUID as bytes (16 bytes).
  """
  def generate_instance_uid do
    Ecto.UUID.bingenerate()
  end

  @doc """
  Generate a random UUID as string.
  """
  def generate_instance_uid_string do
    Ecto.UUID.generate()
  end

  @doc """
  Build a minimal AgentToServer message.
  """
  def build_agent_to_server(attrs \\ %{}) do
    defaults = %{
      instance_uid: generate_instance_uid(),
      sequence_num: 1,
      capabilities: default_agent_capabilities()
    }

    struct(Opamp.Proto.AgentToServer, Map.merge(defaults, attrs))
  end

  @doc """
  Build an AgentToServer with full agent description.
  """
  def build_agent_to_server_with_description(attrs \\ %{}) do
    description = Map.get(attrs, :agent_description) || build_agent_description()

    build_agent_to_server(Map.put(attrs, :agent_description, description))
  end

  @doc """
  Build an AgentToServer with health information.
  """
  def build_agent_to_server_with_health(attrs \\ %{}) do
    health = Map.get(attrs, :health) || build_component_health()

    build_agent_to_server(Map.put(attrs, :health, health))
  end

  @doc """
  Build an AgentToServer with effective config.
  """
  def build_agent_to_server_with_config(attrs \\ %{}) do
    config = Map.get(attrs, :effective_config) || build_effective_config()

    build_agent_to_server(Map.put(attrs, :effective_config, config))
  end

  @doc """
  Build a complete AgentToServer with all fields populated.
  """
  def build_full_agent_to_server(attrs \\ %{}) do
    defaults = %{
      instance_uid: generate_instance_uid(),
      sequence_num: 1,
      agent_description: build_agent_description(),
      capabilities: default_agent_capabilities(),
      health: build_component_health(),
      effective_config: build_effective_config(),
      remote_config_status: build_remote_config_status(),
      flags: 0
    }

    struct(Opamp.Proto.AgentToServer, Map.merge(defaults, attrs))
  end

  @doc """
  Build a ServerToAgent message.
  """
  def build_server_to_agent(attrs \\ %{}) do
    defaults = %{
      instance_uid: generate_instance_uid(),
      capabilities: OpAMPServer.OpAMP.Protocol.Helpers.server_capabilities()
    }

    struct(Opamp.Proto.ServerToAgent, Map.merge(defaults, attrs))
  end

  @doc """
  Build an AgentDescription with sample attributes.
  """
  def build_agent_description(attrs \\ %{}) do
    defaults = %{
      identifying_attributes: [
        build_key_value("service.name", "test-agent"),
        build_key_value("service.version", "1.0.0")
      ],
      non_identifying_attributes: [
        build_key_value("os.type", "linux"),
        build_key_value("host.name", "test-host")
      ]
    }

    struct(Opamp.Proto.AgentDescription, Map.merge(defaults, attrs))
  end

  @doc """
  Build a ComponentHealth message.
  """
  def build_component_health(attrs \\ %{}) do
    defaults = %{
      healthy: true,
      start_time_unix_nano: System.os_time(:nanosecond),
      status: "Running",
      status_time_unix_nano: System.os_time(:nanosecond),
      component_health_map: %{}
    }

    struct(Opamp.Proto.ComponentHealth, Map.merge(defaults, attrs))
  end

  @doc """
  Build a ComponentHealth with nested components.
  """
  def build_component_health_with_children(attrs \\ %{}) do
    children = %{
      "receiver/otlp" => build_component_health(%{status: "Running"}),
      "processor/batch" => build_component_health(%{status: "Running"}),
      "exporter/otlp" =>
        build_component_health(%{
          healthy: false,
          status: "Error",
          last_error: "Connection refused"
        })
    }

    build_component_health(Map.put(attrs, :component_health_map, children))
  end

  @doc """
  Build an EffectiveConfig message.
  """
  def build_effective_config(attrs \\ %{}) do
    config_map = Map.get(attrs, :config_map) || build_agent_config_map()

    %Opamp.Proto.EffectiveConfig{config_map: config_map}
  end

  @doc """
  Build an AgentConfigMap with sample configuration.
  """
  def build_agent_config_map(config_files \\ nil) do
    files =
      config_files ||
        %{
          "collector.yaml" =>
            build_agent_config_file("receivers:\n  otlp:\n    protocols:\n      grpc:\n"),
          "logging.yaml" => build_agent_config_file("level: info\n")
        }

    %Opamp.Proto.AgentConfigMap{config_map: files}
  end

  @doc """
  Build an AgentConfigFile.
  """
  def build_agent_config_file(body, content_type \\ "text/yaml") do
    %Opamp.Proto.AgentConfigFile{
      body: body,
      content_type: content_type
    }
  end

  @doc """
  Build a RemoteConfigStatus message.
  """
  def build_remote_config_status(attrs \\ %{}) do
    defaults = %{
      last_remote_config_hash: :crypto.hash(:md5, "test-config"),
      status: :RemoteConfigStatuses_APPLIED,
      error_message: ""
    }

    struct(Opamp.Proto.RemoteConfigStatus, Map.merge(defaults, attrs))
  end

  @doc """
  Build an AgentRemoteConfig message.
  """
  def build_agent_remote_config(attrs \\ %{}) do
    config = Map.get(attrs, :config) || build_agent_config_map()
    config_hash = :crypto.hash(:md5, Opamp.Proto.AgentConfigMap.encode(config))

    %Opamp.Proto.AgentRemoteConfig{
      config: config,
      config_hash: config_hash
    }
  end

  @doc """
  Build a KeyValue with string value.
  """
  def build_key_value(key, value) when is_binary(value) do
    %Opamp.Proto.KeyValue{
      key: key,
      value: %Opamp.Proto.AnyValue{value: {:string_value, value}}
    }
  end

  @doc """
  Build a KeyValue with integer value.
  """
  def build_key_value_int(key, value) when is_integer(value) do
    %Opamp.Proto.KeyValue{
      key: key,
      value: %Opamp.Proto.AnyValue{value: {:int_value, value}}
    }
  end

  @doc """
  Build a KeyValue with boolean value.
  """
  def build_key_value_bool(key, value) when is_boolean(value) do
    %Opamp.Proto.KeyValue{
      key: key,
      value: %Opamp.Proto.AnyValue{value: {:bool_value, value}}
    }
  end

  @doc """
  Build a KeyValue with double value.
  """
  def build_key_value_double(key, value) when is_float(value) do
    %Opamp.Proto.KeyValue{
      key: key,
      value: %Opamp.Proto.AnyValue{value: {:double_value, value}}
    }
  end

  @doc """
  Build a KeyValue with array value.
  """
  def build_key_value_array(key, values) when is_list(values) do
    any_values =
      Enum.map(values, fn
        v when is_binary(v) -> %Opamp.Proto.AnyValue{value: {:string_value, v}}
        v when is_integer(v) -> %Opamp.Proto.AnyValue{value: {:int_value, v}}
        v when is_boolean(v) -> %Opamp.Proto.AnyValue{value: {:bool_value, v}}
        v when is_float(v) -> %Opamp.Proto.AnyValue{value: {:double_value, v}}
      end)

    %Opamp.Proto.KeyValue{
      key: key,
      value: %Opamp.Proto.AnyValue{
        value: {:array_value, %Opamp.Proto.ArrayValue{values: any_values}}
      }
    }
  end

  @doc """
  Build a KeyValue with nested key-value list.
  """
  def build_key_value_map(key, map) when is_map(map) do
    kv_list =
      Enum.map(map, fn {k, v} ->
        build_key_value(to_string(k), to_string(v))
      end)

    %Opamp.Proto.KeyValue{
      key: key,
      value: %Opamp.Proto.AnyValue{
        value: {:kvlist_value, %Opamp.Proto.KeyValueList{values: kv_list}}
      }
    }
  end

  @doc """
  Build an AnyValue from an Elixir term.
  """
  def build_any_value(value) when is_binary(value) do
    %Opamp.Proto.AnyValue{value: {:string_value, value}}
  end

  def build_any_value(value) when is_integer(value) do
    %Opamp.Proto.AnyValue{value: {:int_value, value}}
  end

  def build_any_value(value) when is_boolean(value) do
    %Opamp.Proto.AnyValue{value: {:bool_value, value}}
  end

  def build_any_value(value) when is_float(value) do
    %Opamp.Proto.AnyValue{value: {:double_value, value}}
  end

  def build_any_value(nil) do
    %Opamp.Proto.AnyValue{value: nil}
  end

  @doc """
  Build a ServerErrorResponse.
  """
  def build_server_error_response(type, message) do
    %Opamp.Proto.ServerErrorResponse{
      type: type,
      error_message: message
    }
  end

  @doc """
  Build AvailableComponents message.
  """
  def build_available_components(attrs \\ %{}) do
    components =
      Map.get(attrs, :components) ||
        %{
          "receiver/otlp" =>
            build_component_details(%{metadata: [build_key_value("version", "0.90.0")]}),
          "processor/batch" =>
            build_component_details(%{metadata: [build_key_value("version", "0.90.0")]})
        }

    hash = Map.get(attrs, :hash) || :crypto.hash(:md5, "components")

    %Opamp.Proto.AvailableComponents{
      components: components,
      hash: hash
    }
  end

  @doc """
  Build ComponentDetails message.
  """
  def build_component_details(attrs \\ %{}) do
    defaults = %{
      metadata: [],
      sub_component_map: %{}
    }

    struct(Opamp.Proto.ComponentDetails, Map.merge(defaults, attrs))
  end

  @doc """
  Build a ConnectionSettingsOffers message.
  """
  def build_connection_settings_offers(attrs \\ %{}) do
    defaults = %{
      hash: :crypto.hash(:md5, "settings"),
      opamp: nil,
      own_metrics: nil,
      own_traces: nil,
      own_logs: nil,
      other_connections: %{}
    }

    struct(Opamp.Proto.ConnectionSettingsOffers, Map.merge(defaults, attrs))
  end

  @doc """
  Build OpAMPConnectionSettings message.
  """
  def build_opamp_connection_settings(attrs \\ %{}) do
    defaults = %{
      destination_endpoint: "wss://opamp.example.com/v1/opamp",
      headers: nil,
      certificate: nil,
      heartbeat_interval_seconds: 30,
      tls: nil
    }

    struct(Opamp.Proto.OpAMPConnectionSettings, Map.merge(defaults, attrs))
  end

  @doc """
  Build TLSConnectionSettings message.
  """
  def build_tls_connection_settings(attrs \\ %{}) do
    defaults = %{
      ca_pem_contents: "",
      include_system_ca_certs_pool: true,
      insecure_skip_verify: false,
      min_version: "1.2",
      max_version: "1.3",
      cipher_suites: []
    }

    struct(Opamp.Proto.TLSConnectionSettings, Map.merge(defaults, attrs))
  end

  @doc """
  Build PackagesAvailable message.
  """
  def build_packages_available(attrs \\ %{}) do
    packages =
      Map.get(attrs, :packages) ||
        %{
          "collector" => build_package_available(%{version: "0.90.0"})
        }

    %Opamp.Proto.PackagesAvailable{
      packages: packages,
      all_packages_hash: :crypto.hash(:md5, "packages")
    }
  end

  @doc """
  Build PackageAvailable message.
  """
  def build_package_available(attrs \\ %{}) do
    defaults = %{
      type: :PackageType_TopLevel,
      version: "1.0.0",
      file: build_downloadable_file(),
      hash: :crypto.hash(:md5, "package")
    }

    struct(Opamp.Proto.PackageAvailable, Map.merge(defaults, attrs))
  end

  @doc """
  Build DownloadableFile message.
  """
  def build_downloadable_file(attrs \\ %{}) do
    defaults = %{
      download_url: "https://example.com/package.tar.gz",
      content_hash: :crypto.hash(:sha256, "content"),
      signature: <<>>,
      headers: nil
    }

    struct(Opamp.Proto.DownloadableFile, Map.merge(defaults, attrs))
  end

  @doc """
  Encode an AgentToServer message with the OpAMP binary header.
  """
  def encode_with_header(%Opamp.Proto.AgentToServer{} = message) do
    <<0>> <> Opamp.Proto.AgentToServer.encode(message)
  end

  @doc """
  Default agent capabilities bitmask.
  """
  def default_agent_capabilities do
    import Bitwise

    cap_to_int(Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus)
    |> bor(cap_to_int(Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsRemoteConfig))
    |> bor(cap_to_int(Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsEffectiveConfig))
    |> bor(cap_to_int(Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHealth))
  end

  @doc """
  All agent capabilities bitmask.
  """
  def all_agent_capabilities do
    import Bitwise

    [
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsRemoteConfig,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsEffectiveConfig,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsPackages,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsPackageStatuses,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsOwnTraces,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsOwnMetrics,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsOwnLogs,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsOpAMPConnectionSettings,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsOtherConnectionSettings,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsRestartCommand,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHealth,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsRemoteConfig,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHeartbeat,
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsAvailableComponents
    ]
    |> Enum.map(&cap_to_int/1)
    |> Enum.reduce(0, &bor/2)
  end

  # Helper to convert capability to int (avoiding circular dependency)
  defp cap_to_int(cap) do
    OpAMPServer.OpAMP.Protocol.Helpers.agent_capability_to_int(cap)
  end
end
