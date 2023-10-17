defmodule OpAMPServerWeb.Serializer do
  @behaviour Phoenix.Socket.Serializer

  alias Phoenix.Socket.Reply
  alias Phoenix.Socket.Message
  alias Phoenix.Socket.Broadcast

  @push 0
  @reply 1
  @broadcast 2

  def fastlane!(%Broadcast{} = msg) do
    msg = %Message{topic: msg.topic, event: msg.event, payload: msg.payload}

    {:socket_push, :binary, encode_to_binary(msg)}
  end

  def encode!(%Reply{} = reply) do
    {:socket_push, :binary, Opamp.Proto.ServerToAgent.encode(reply.payload)}
  end
  
  def encode!(%Message{} = msg) do
    IO.puts "decoding"
    IO.puts "encode!!!"
    {:socket_push, :binary, encode_to_binary(msg)}
  end

  defp encode_to_binary(msg) do
    msg |> Map.from_struct()
  end

  def decode!(raw_message, opts) do
    case Keyword.fetch(opts, :opcode) do
      {:ok, :text} -> decode_text(raw_message)
      {:ok, :binary} -> decode_binary(raw_message)
    end
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

  defp decode_binary(<<
         _header::size(8),
         data::binary
       >>) do
    proto = Opamp.Proto.AgentToServer.decode(data)
    %Message{
      topic: "agents:" <> proto.instance_uid,
      event: "phx_join",
      payload: proto,
      ref: proto.sequence_num,
      join_ref: "join"
    }
  end
end