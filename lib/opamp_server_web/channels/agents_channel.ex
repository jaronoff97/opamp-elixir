defmodule OpAMPServerWeb.AgentsChannel do
  alias OpAMPServerWeb.BridgeAgent
  use OpAMPServerWeb, :channel

  @impl true
  def join("agents:" <> agent_id, payload, socket) do
    OpAMPServer.Agents.subscribe()
    server_to_agent = BridgeAgent.start_link(agent_id, %{})
    BridgeAgent.put(:opampagent, agent_id, payload.effective_config)
    {:ok, server_to_agent, socket
      |> assign(:agent_id, agent_id)}
  end

  @impl true
  def handle_info({:agent_created, _payload}, socket) do
    {:noreply, socket}
  end
  @impl true
  def handle_info({:agent_deleted, _payload}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_updated, payload}, socket) do
    # BridgeAgent.put(:opampagent, socket.assigns.agent_id, payload.effective_config)
    # IO.puts "I AM SENDING AN UPDATE MESSAGE OMG"
    server_to_agent = %Opamp.Proto.ServerToAgent{
      instance_uid: socket.assigns.agent_id,
      capabilities: BridgeAgent.server_capabilities(),
      remote_config: %Opamp.Proto.AgentRemoteConfig{
        config_hash: :crypto.hash(:md5, Opamp.Proto.AgentConfigMap.encode(payload.effective_config.config_map)),
        config: payload.effective_config.config_map
      }
    }
    # IO.puts "------------ configmap pre-send"
    # IO.inspect(payload.effective_config.config_map)
    # IO.puts "------------ configmap pre-send"
    push(socket, "", server_to_agent)
    {:noreply, socket}
  end

  # Channels can be used in a request/response fashion
  # by sending replies to requests from the client
  @impl true
  def handle_in("ping", _payload, socket) do
    server_to_agent = %Opamp.Proto.ServerToAgent{
      instance_uid: socket.assigns.agent_id,
      capabilities: BridgeAgent.server_capabilities()
    }
    {:reply, server_to_agent, socket}
  end

  @impl true
  def handle_in("heartbeat", payload, socket) do
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
    BridgeAgent.delete(:opampagent, socket.assigns.agent_id)
    OpAMPServerWeb.Serializer.remove(socket.assigns.agent_id)
    {:shutdown, socket.assigns.agent_id}
  end
end
