defmodule OpAMPServer.OpAMP.Protocol.Encoder do
  @moduledoc """
  OpAMP protocol message encoder.

  Handles encoding of ServerToAgent messages to binary format.
  """

  alias OpAMPServer.OpAMP.Protocol.Helpers

  @doc """
  Build a ServerToAgent response message.

  ## Options
    * `:capabilities` - Override server capabilities (default: all supported)
    * `:remote_config` - Include remote config in response
    * `:flags` - Server flags to include
    * `:error_response` - Include an error response
  """
  def build_server_to_agent(agent_id, opts \\ []) do
    capabilities = Keyword.get(opts, :capabilities, Helpers.server_capabilities())
    remote_config = Keyword.get(opts, :remote_config)
    flags = Keyword.get(opts, :flags)
    error_response = Keyword.get(opts, :error_response)

    %Opamp.Proto.ServerToAgent{
      instance_uid: agent_id,
      capabilities: capabilities
    }
    |> maybe_add_remote_config(remote_config)
    |> maybe_add_flags(flags)
    |> maybe_add_error(error_response)
  end

  @doc """
  Build an error response for common error scenarios.
  """
  def build_error_response(:unmatched_topic) do
    %Opamp.Proto.ServerToAgent{
      error_response: %Opamp.Proto.ServerErrorResponse{
        type: :ServerErrorResponseType_Unavailable,
        error_message: "Connection idled, reconnect requested"
      }
    }
  end

  def build_error_response({:unavailable, message}) do
    %Opamp.Proto.ServerToAgent{
      error_response: %Opamp.Proto.ServerErrorResponse{
        type: :ServerErrorResponseType_Unavailable,
        error_message: message
      }
    }
  end

  def build_error_response({:bad_request, message}) do
    %Opamp.Proto.ServerToAgent{
      error_response: %Opamp.Proto.ServerErrorResponse{
        type: :ServerErrorResponseType_BadRequest,
        error_message: message
      }
    }
  end

  def build_error_response(reason) when is_binary(reason) do
    %Opamp.Proto.ServerToAgent{
      error_response: %Opamp.Proto.ServerErrorResponse{
        type: :ServerErrorResponseType_Unavailable,
        error_message: reason
      }
    }
  end

  @doc """
  Encode a ServerToAgent struct to binary.
  """
  def encode(%Opamp.Proto.ServerToAgent{} = message) do
    Opamp.Proto.ServerToAgent.encode(message)
  end

  @doc """
  Encode an AgentConfigMap to binary (useful for hashing).
  """
  def encode_config_map(%Opamp.Proto.AgentConfigMap{} = config_map) do
    Opamp.Proto.AgentConfigMap.encode(config_map)
  end

  # Private helpers

  defp maybe_add_remote_config(message, nil), do: message

  defp maybe_add_remote_config(message, config) do
    %{message | remote_config: config}
  end

  defp maybe_add_flags(message, nil), do: message

  defp maybe_add_flags(message, flags) do
    %{message | flags: flags}
  end

  defp maybe_add_error(message, nil), do: message

  defp maybe_add_error(message, error) do
    %{message | error_response: error}
  end
end
