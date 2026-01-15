defmodule OpAMPServer.OpAMP.Protocol.Helpers do
  @moduledoc """
  OpAMP protocol helper functions.

  Provides utilities for capability encoding/decoding, attribute conversion,
  and other protocol-related operations.
  """

  import Bitwise

  # Server capabilities
  @server_capabilities [
    Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsStatus,
    Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersRemoteConfig,
    Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsEffectiveConfig,
    Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersConnectionSettings,
    Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsConnectionSettingsRequest
  ]

  @doc """
  Returns the bitmask of all supported server capabilities.
  """
  def server_capabilities do
    @server_capabilities
    |> Enum.map(&server_capability_to_int/1)
    |> Enum.reduce(0, &bor/2)
  end

  @doc """
  Convert a server capability enum to its integer value.
  """
  def server_capability_to_int(capability) do
    case capability do
      Opamp.Proto.ServerCapabilities.ServerCapabilities_Unspecified -> 0
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsStatus -> 1
      Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersRemoteConfig -> 2
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsEffectiveConfig -> 4
      Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersPackages -> 8
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsPackagesStatus -> 16
      Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersConnectionSettings -> 32
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsConnectionSettingsRequest -> 64
      _ -> 0
    end
  end

  @doc """
  Convert an agent capability enum to its integer value.
  """
  def agent_capability_to_int(capability) do
    case capability do
      Opamp.Proto.AgentCapabilities.AgentCapabilities_Unspecified -> 0
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus -> 1
      Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsRemoteConfig -> 2
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsEffectiveConfig -> 4
      Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsPackages -> 8
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsPackageStatuses -> 16
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsOwnTraces -> 32
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsOwnMetrics -> 64
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsOwnLogs -> 128
      Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsOpAMPConnectionSettings -> 256
      Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsOtherConnectionSettings -> 512
      Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsRestartCommand -> 1024
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHealth -> 2048
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsRemoteConfig -> 4096
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHeartbeat -> 8192
      Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsAvailableComponents -> 16384
      _ -> 0
    end
  end

  @doc """
  Check if an agent has a specific capability.
  """
  def agent_has_capability?(agent_to_server, requested_capability) do
    case Map.get(agent_to_server, :capabilities) do
      capabilities when is_integer(capabilities) ->
        (capabilities &&& agent_capability_to_int(requested_capability)) != 0

      _ ->
        false
    end
  end

  @doc """
  Convert ServerToAgentFlags enum to integer bitmask.
  """
  def server_flags_to_int(flags) when is_list(flags) do
    flags
    |> Enum.map(&server_flag_to_int/1)
    |> Enum.reduce(0, &bor/2)
  end

  def server_flags_to_int(flag), do: server_flag_to_int(flag)

  defp server_flag_to_int(flag) do
    case flag do
      Opamp.Proto.ServerToAgentFlags.ServerToAgentFlags_Unspecified -> 0
      Opamp.Proto.ServerToAgentFlags.ServerToAgentFlags_ReportFullState -> 1
      Opamp.Proto.ServerToAgentFlags.ServerToAgentFlags_ReportAvailableComponents -> 2
      _ -> 0
    end
  end

  @doc """
  Convert proto KeyValue list to an Elixir map.

  ## Options
    * `:cast_string` - Cast boolean/integer values to strings (default: false)
  """
  def attributes_to_map(attributes, opts \\ []) do
    Enum.reduce(attributes, %{}, fn %Opamp.Proto.KeyValue{key: key, value: value}, acc ->
      Map.put(acc, key, clean_any_value(value, opts))
    end)
  end

  @doc """
  Convert an AnyValue proto to its native Elixir representation.
  """
  def clean_any_value(nil, _opts), do: nil

  def clean_any_value(%Opamp.Proto.AnyValue{value: {:string_value, value}}, _opts), do: value

  def clean_any_value(%Opamp.Proto.AnyValue{value: {:bool_value, value}}, opts) do
    case Keyword.get(opts, :cast_string, false) do
      true -> to_string(value)
      false -> value
    end
  end

  def clean_any_value(%Opamp.Proto.AnyValue{value: {:int_value, value}}, opts) do
    case Keyword.get(opts, :cast_string, false) do
      true -> to_string(value)
      false -> value
    end
  end

  def clean_any_value(%Opamp.Proto.AnyValue{value: {:double_value, value}}, opts) do
    case Keyword.get(opts, :cast_string, false) do
      true -> to_string(value)
      false -> value
    end
  end

  def clean_any_value(%Opamp.Proto.AnyValue{value: {:bytes_value, value}}, _opts), do: value

  def clean_any_value(
        %Opamp.Proto.AnyValue{value: {:array_value, %Opamp.Proto.ArrayValue{values: values}}},
        opts
      ) do
    Enum.map(values, &clean_any_value(&1, opts))
  end

  def clean_any_value(
        %Opamp.Proto.AnyValue{
          value: {:kvlist_value, %Opamp.Proto.KeyValueList{values: kv_values}}
        },
        opts
      ) do
    Enum.reduce(kv_values, %{}, fn %Opamp.Proto.KeyValue{key: key, value: value}, acc ->
      Map.put(acc, key, clean_any_value(value, opts))
    end)
  end

  def clean_any_value(%Opamp.Proto.AnyValue{value: nil}, _opts), do: nil

  @doc """
  Generate an MD5 hash of an AgentConfigMap for change detection.
  """
  def config_hash(%Opamp.Proto.AgentConfigMap{} = config_map) do
    :crypto.hash(:md5, Opamp.Proto.AgentConfigMap.encode(config_map))
  end
end
