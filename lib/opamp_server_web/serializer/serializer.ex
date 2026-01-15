defmodule OpAMPServerWeb.Serializer do
  @moduledoc """
  Phoenix WebSocket serializer for OpAMP protocol.

  This is a thin adapter that bridges Phoenix's serialization interface
  with the OpAMP protocol layer. All protocol logic is delegated to
  OpAMPServer.OpAMP.Protocol modules.
  """

  @behaviour Phoenix.Socket.Serializer

  alias Phoenix.Socket.{Reply, Message, Broadcast}
  alias OpAMPServer.OpAMP.Protocol
  alias OpAMPServer.OpAMP.Protocol.Encoder
  alias OpAMPServer.OpAMP.ConnectionManager

  @doc """
  Encode a broadcast message for fast-path delivery.
  """
  def fastlane!(%Broadcast{} = msg) do
    {:socket_push, :binary, encode_payload(msg.payload)}
  end

  @doc """
  Encode a reply or regular message.
  """
  def encode!(%Reply{} = reply) do
    payload =
      case reply.status do
        :error -> build_error_payload(reply.payload)
        _ -> reply.payload
      end

    {:socket_push, :binary, encode_payload(payload)}
  end

  def encode!(%Message{} = msg) do
    {:socket_push, :binary, encode_payload(msg.payload)}
  end

  @doc """
  Decode an incoming WebSocket message.
  """
  def decode!(raw_message, opts) do
    case Keyword.fetch(opts, :opcode) do
      {:ok, :text} -> decode_text(raw_message)
      {:ok, :binary} -> decode_binary(raw_message)
    end
  end

  # Private functions

  defp encode_payload(%{reason: _} = data) do
    :erlang.term_to_binary(data)
  end

  defp encode_payload(data) when is_map(data) and map_size(data) == 0 do
    :erlang.term_to_binary(data)
  end

  defp encode_payload(%Opamp.Proto.ServerToAgent{} = payload) do
    Encoder.encode(payload)
  end

  defp build_error_payload(%{reason: "unmatched topic"}) do
    Protocol.build_error_response(:unmatched_topic)
  end

  defp build_error_payload(%{reason: reason}) do
    Protocol.build_error_response(reason)
  end

  defp decode_text(raw_message) do
    [join_ref, ref, topic, event, payload | _] = Phoenix.json_library().decode!(raw_message)

    %Message{
      topic: topic,
      event: event,
      payload: payload,
      ref: ref,
      join_ref: join_ref
    }
  end

  defp decode_binary(<<_header::size(8), data::binary>>) do
    proto = Opamp.Proto.AgentToServer.decode(data)
    instance_uuid = Ecto.UUID.load!(proto.instance_uid)

    case ConnectionManager.is_new_connection?(instance_uuid) do
      true -> handle_join(proto, instance_uuid)
      false -> handle_heartbeat(proto, instance_uuid)
    end
  end

  defp handle_join(proto, instance_uuid) do
    ConnectionManager.register(instance_uuid)

    %Message{
      topic: "agents:" <> instance_uuid,
      event: "phx_join",
      payload: proto,
      ref: proto.sequence_num,
      join_ref: "join"
    }
  end

  defp handle_heartbeat(proto, instance_uuid) when proto.sequence_num > 0 do
    %Message{
      topic: "agents:" <> instance_uuid,
      event: "heartbeat",
      payload: proto,
      ref: proto.sequence_num,
      join_ref: "beat"
    }
  end
end
