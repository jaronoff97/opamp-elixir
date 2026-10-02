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
  alias OpAMPServer.OpAMP.Protocol.{Decoder, Encoder}

  require Logger

  # No channel matches this topic, so Phoenix answers with an "unmatched topic"
  # error reply, which encode!/1 turns into a BadRequest.
  @bad_request_topic "opamp:bad_request"

  @doc """
  Encode a broadcast message for fast-path delivery.
  """
  def fastlane!(%Broadcast{} = msg) do
    {:socket_push, :binary, encode_payload(msg.payload)}
  end

  @doc """
  Encode a reply or regular message.
  """
  # The serializer runs in the socket process, so the process dictionary holds the
  # join state of this connection only. Forget the join when the channel is gone,
  # so that the next message from the agent joins again.
  def encode!(%Reply{topic: @bad_request_topic}) do
    {:socket_push, :binary,
     encode_payload(
       Protocol.build_error_response({:bad_request, "malformed AgentToServer message"})
     )}
  end

  def encode!(%Reply{status: :error, payload: %{reason: "unmatched topic"}} = reply) do
    Process.delete({__MODULE__, reply.topic})
    {:socket_push, :binary, encode_payload(build_error_payload(reply.payload))}
  end

  def encode!(%Reply{} = reply) do
    payload =
      case reply.status do
        :error -> build_error_payload(reply.payload)
        _ -> reply.payload
      end

    {:socket_push, :binary, encode_payload(payload)}
  end

  def encode!(%Message{event: event} = msg) when event in ["phx_error", "phx_close"] do
    Process.delete({__MODULE__, msg.topic})
    {:socket_push, :binary, encode_payload(msg.payload)}
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

  defp decode_binary(raw_message) do
    case Decoder.decode_agent_message(raw_message) do
      {:ok, proto, instance_uuid} ->
        # Process.put/2 returns the old value: nil means this connection has not joined yet.
        case Process.put({__MODULE__, "agents:" <> instance_uuid}, true) do
          nil -> handle_join(proto, instance_uuid)
          true -> handle_heartbeat(proto, instance_uuid)
        end

      {:error, reason} ->
        Logger.warning("Malformed AgentToServer message: #{inspect(reason)}")
        %Message{topic: @bad_request_topic, event: "bad_request", payload: %{}}
    end
  end

  # Phoenix 1.8 drops a message to a joined topic if its join_ref is not the join_ref of the
  # join ("a stale message to a previous join_ref"). So every message uses the same one.
  @join_ref "join"

  defp handle_join(proto, instance_uuid) do
    %Message{
      topic: "agents:" <> instance_uuid,
      event: "phx_join",
      payload: proto,
      ref: proto.sequence_num,
      join_ref: @join_ref
    }
  end

  defp handle_heartbeat(proto, instance_uuid) do
    %Message{
      topic: "agents:" <> instance_uuid,
      event: "heartbeat",
      payload: proto,
      ref: proto.sequence_num,
      join_ref: @join_ref
    }
  end
end
