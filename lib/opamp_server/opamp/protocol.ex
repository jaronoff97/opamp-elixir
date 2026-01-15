defmodule OpAMPServer.OpAMP.Protocol do
  @moduledoc """
  Core OpAMP protocol handling module.

  This module provides the main entry point for processing OpAMP messages,
  isolating protocol logic from transport concerns (Phoenix channels, WebSockets, etc.).
  """

  alias OpAMPServer.OpAMP.Protocol.Decoder
  alias OpAMPServer.OpAMP.Protocol.Encoder
  alias OpAMPServer.OpAMP.Protocol.Helpers
  alias OpAMPServer.OpAMP.ConnectionManager

  @doc """
  Process an incoming binary OpAMP message.

  Returns `{:join, agent_id, proto, response}` for new connections
  or `{:message, agent_id, proto, response}` for existing connections.
  """
  def process_message(binary) do
    with {:ok, proto, agent_id} <- Decoder.decode_agent_message(binary),
         is_new <- ConnectionManager.is_new_connection?(agent_id) do
      if is_new do
        ConnectionManager.register(agent_id)
        {:join, agent_id, proto}
      else
        {:message, agent_id, proto}
      end
    end
  end

  @doc """
  Build a ServerToAgent response message.
  """
  def build_response(agent_id, opts \\ []) do
    Encoder.build_server_to_agent(agent_id, opts)
  end

  @doc """
  Build an error response message.
  """
  def build_error_response(reason) do
    Encoder.build_error_response(reason)
  end

  @doc """
  Encode a ServerToAgent message to binary.
  """
  def encode(message) do
    Encoder.encode(message)
  end

  @doc """
  Get the server capabilities bitmask.
  """
  defdelegate server_capabilities, to: Helpers

  @doc """
  Check if an agent has a specific capability.
  """
  defdelegate agent_has_capability?(agent_to_server, capability), to: Helpers

  @doc """
  Convert proto attributes to a map.
  """
  defdelegate attributes_to_map(attributes, opts \\ []), to: Helpers
end
