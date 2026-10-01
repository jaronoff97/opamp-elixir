defmodule OpAMPServer.OpAMP.Protocol do
  @moduledoc """
  Core OpAMP protocol handling module.

  This module provides the main entry point for processing OpAMP messages,
  isolating protocol logic from transport concerns (Phoenix channels, WebSockets, etc.).
  """

  alias OpAMPServer.OpAMP.Protocol.Encoder
  alias OpAMPServer.OpAMP.Protocol.Helpers

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
