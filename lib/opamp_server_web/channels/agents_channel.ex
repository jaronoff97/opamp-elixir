defmodule OpAMPServerWeb.AgentsChannel do
  @moduledoc """
  Phoenix Channel for handling OpAMP agent connections.

  This channel handles the Phoenix-specific aspects of agent communication,
  delegating protocol logic to the OpAMP.Protocol layer.
  """

  use OpAMPServerWeb, :channel

  alias OpAMPServer.OpAMP.Protocol.Helpers
  alias OpAMPServer.OpAMP.ConnectionManager

  @impl true
  def join("agents:" <> agent_id, payload, socket) do
    OpAMPServer.Agents.subscribe()

    server_to_agent =
      agent_id
      |> create_or_update(payload)
      |> generate_response()

    {:ok, server_to_agent, assign(socket, :agent_id, agent_id)}
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
    server_to_agent = %Opamp.Proto.ServerToAgent{
      instance_uid: socket.assigns.agent_id,
      capabilities: Helpers.server_capabilities(),
      remote_config: payload.desired_remote_config
    }

    push(socket, "", server_to_agent)
    {:noreply, socket}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    server_to_agent = %Opamp.Proto.ServerToAgent{
      instance_uid: socket.assigns.agent_id,
      capabilities: Helpers.server_capabilities()
    }

    {:reply, {:ok, server_to_agent}, socket}
  end

  @impl true
  def handle_in("heartbeat", payload, socket) do
    create_or_update(socket.assigns.agent_id, payload)

    server_to_agent = %Opamp.Proto.ServerToAgent{
      instance_uid: socket.assigns.agent_id,
      capabilities: Helpers.server_capabilities()
    }

    {:reply, {:ok, server_to_agent}, socket}
  end

  @impl true
  def handle_in("shout", payload, socket) do
    broadcast(socket, "shout", payload)
    {:noreply, socket}
  end

  @impl true
  def terminate(reason, socket) do
    case reason do
      {:shutdown, :timeout} ->
        IO.puts("#{socket.assigns.agent_id} timed out")

      {:shutdown, :peer_closed} ->
        IO.puts("#{socket.assigns.agent_id} disconnected")

      other ->
        IO.inspect(other)
    end

    delete(socket.assigns.agent_id)
    {:shutdown, socket.assigns.agent_id}
  end

  # Private functions

  defp delete(agent_id) do
    case OpAMPServer.Agents.get_agent(agent_id) do
      nil ->
        {:error, "not found"}

      agent ->
        ConnectionManager.unregister(agent_id)
        OpAMPServer.Agents.delete_agent(agent)
    end
  end

  defp create_or_update(agent_id, payload) do
    attrs = %{
      id: agent_id,
      effective_config: payload.effective_config,
      remote_config_status: payload.remote_config_status,
      component_health: payload.health,
      description: payload.agent_description
    }

    case OpAMPServer.Agents.get_agent(agent_id) do
      nil -> OpAMPServer.Agents.create_agent(attrs)
      agent -> OpAMPServer.Agents.update_agent(agent, attrs)
    end
  end

  defp generate_response({:ok, agent}) do
    %Opamp.Proto.ServerToAgent{
      instance_uid: agent.id,
      capabilities: Helpers.server_capabilities()
    }
  end

  defp generate_response({:error, _changeset} = error) do
    # Log error but still return a response
    IO.inspect(error, label: "Agent create/update error")

    %Opamp.Proto.ServerToAgent{
      capabilities: Helpers.server_capabilities()
    }
  end
end
