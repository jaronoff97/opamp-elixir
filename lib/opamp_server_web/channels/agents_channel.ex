defmodule OpAMPServerWeb.AgentsChannel do
  alias OpAMPServerWeb.BridgeAgent
  use OpAMPServerWeb, :channel

  @impl true
  def join("agents:" <> agent_id, payload, socket) do
    IO.puts "----joining----"
    IO.inspect agent_id
    IO.inspect payload
    IO.puts "----end joining----"
    server_to_agent = BridgeAgent.start_link(agent_id, %{})
    BridgeAgent.put(:opampagent, agent_id, payload.effective_config)
    {:ok, server_to_agent, socket
      |> assign(:agent_id, agent_id)}
  end

  # Channels can be used in a request/response fashion
  # by sending replies to requests from the client
  @impl true
  def handle_in("ping", payload, socket) do
    IO.puts "----handle in----"
    IO.inspect payload
    IO.puts "----ping----"
    {:reply, {:ok, payload}, socket}
  end

  # It is also common to receive messages from the client and
  # broadcast to everyone in the current topic (agents:lobby).
  @impl true
  def handle_in("shout", payload, socket) do
    broadcast(socket, "shout", payload)
    {:noreply, socket}
  end

  @impl true
  def terminate(reason, socket) do
    IO.inspect reason
    IO.inspect socket
    BridgeAgent.delete(:opampagent, socket.assigns.agent_id)
    :ok
  end
end
