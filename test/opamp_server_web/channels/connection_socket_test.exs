defmodule OpAMPServerWeb.ConnectionSocketTest do
  @moduledoc """
  Sends OpAMP frames through the real socket stack: the serializer, Phoenix.Socket and the
  agents channel. The test process acts as the WebSocket transport.
  """
  use OpAMPServerWeb.ChannelCase
  use OpAMPServer.OpAMPCase

  alias OpAMPServerWeb.ConnectionSocket

  defp connect! do
    {:ok, state} =
      ConnectionSocket.connect(%{
        endpoint: OpAMPServerWeb.Endpoint,
        transport: :websocket,
        options: [serializer: [{OpAMPServerWeb.Serializer, "1.0.0"}]],
        params: %{},
        connect_info: %{}
      })

    {:ok, state} = ConnectionSocket.init(state)
    state
  end

  defp frame(message), do: {encode_with_header(message), opcode: :binary}

  test "a heartbeat after the join reaches the channel", _ do
    uid = generate_instance_uid()
    id = Ecto.UUID.load!(uid)
    state = connect!()

    {:reply, :ok, {:binary, join_reply}, state} =
      ConnectionSocket.handle_in(
        frame(build_agent_to_server(%{instance_uid: uid, sequence_num: 1})),
        state
      )

    assert decode_server_to_agent(join_reply).instance_uid == uid

    heartbeat =
      build_agent_to_server(%{
        instance_uid: uid,
        sequence_num: 2,
        agent_description: build_agent_description()
      })

    {:ok, _state} = ConnectionSocket.handle_in(frame(heartbeat), state)

    # The channel replies to the heartbeat, and stores what the heartbeat reported.
    assert_receive {:socket_push, :binary, reply}
    assert decode_server_to_agent(reply).instance_uid == uid
    assert OpAMPServer.Agents.get_agent(id).description.identifying_attributes != []
  end

  test "a malformed frame gets a BadRequest", _ do
    state = connect!()

    {:reply, :error, {:binary, reply}, _state} =
      ConnectionSocket.handle_in({<<0, 255, 255>>, opcode: :binary}, state)

    assert decode_server_to_agent(reply).error_response.type ==
             :ServerErrorResponseType_BadRequest
  end
end
