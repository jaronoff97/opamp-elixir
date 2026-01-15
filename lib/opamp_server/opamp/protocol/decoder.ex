defmodule OpAMPServer.OpAMP.Protocol.Decoder do
  @moduledoc """
  OpAMP protocol message decoder.

  Handles decoding of binary OpAMP messages (AgentToServer) from agents.
  """

  alias Ecto.UUID

  @doc """
  Decode a binary OpAMP message.

  Returns `{:ok, proto, agent_id}` on success or `{:error, reason}` on failure.
  """
  def decode_agent_message(<<_header::size(8), data::binary>>) do
    try do
      proto = Opamp.Proto.AgentToServer.decode(data)
      agent_id = UUID.load!(proto.instance_uid)
      {:ok, proto, agent_id}
    rescue
      e -> {:error, {:decode_error, e}}
    end
  end

  def decode_agent_message(_invalid) do
    {:error, :invalid_message_format}
  end

  @doc """
  Decode a raw protobuf binary (without header) into AgentToServer.
  """
  def decode_raw(data) do
    try do
      {:ok, Opamp.Proto.AgentToServer.decode(data)}
    rescue
      e -> {:error, {:decode_error, e}}
    end
  end
end
