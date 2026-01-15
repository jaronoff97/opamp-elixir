defmodule OpAMPServerWeb.AgentsChannelTest do
  use OpAMPServerWeb.ChannelCase
  use OpAMPServer.OpAMPCase

  setup do
    # Create a proper proto payload for joining
    agent_id = generate_instance_uid_string()
    payload = build_agent_to_server_with_description()

    {:ok, _, socket} =
      OpAMPServerWeb.UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(OpAMPServerWeb.AgentsChannel, "agents:" <> agent_id, payload)

    %{socket: socket, agent_id: agent_id}
  end

  test "ping replies with server_to_agent", %{socket: socket} do
    ref = push(socket, "ping", %{})
    assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{}
  end

  test "heartbeat replies with server_to_agent", %{socket: socket} do
    payload = build_agent_to_server(%{sequence_num: 2})
    ref = push(socket, "heartbeat", payload)
    assert_reply ref, :ok, %Opamp.Proto.ServerToAgent{}
  end

  test "shout broadcasts to channel", %{socket: socket} do
    push(socket, "shout", %{"hello" => "all"})
    assert_broadcast "shout", %{"hello" => "all"}
  end
end
