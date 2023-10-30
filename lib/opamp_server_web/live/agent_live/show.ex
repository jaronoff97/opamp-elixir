defmodule OpAMPServerWeb.AgentLive.Show do
  use OpAMPServerWeb, :live_view
  import Phoenix.HTML.Form

  alias OpAMPServer.Agents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Agents.get_agent(id) do
      nil -> {:ok, redirect(socket, to: ~p"/agent")}
      agent ->
        if connected?(socket), do: OpAMPServer.Agents.subscribe_to_agent(id)
        {:ok, socket
              |> assign_initial_changeset(agent)
              |> assign(:agent_id, id)
              |> assign(:collector, "") }
    end
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    agent = Agents.get_agent!(id)
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:agent, agent)
     |> assign(map_keys: Map.keys(agent.effective_config.config_map.config_map))}
  end

  @impl true
  def handle_info({:agent_created, _agent}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_updated, agent}, socket) do
    if agent.remote_config_status != nil do
      {:noreply, socket 
                  |> assign_initial_changeset(agent)
                  |> set_flash(agent.remote_config_status)}
    else
      {:noreply, assign_initial_changeset(socket, agent)}
    end
  end

  @impl true
  def handle_info({:agent_deleted, _agent}, socket) do
    {:noreply, redirect(socket, to: ~p"/agent")}
  end

  @impl true
  def handle_event("validate", %{"agent" => _changed}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select", %{"collector" => collector}, socket) do
    {:noreply, socket
      |> assign(:collector, collector)}
  end

  @impl true
  def handle_event("save", %{"agent" => %{"effective_config" => new_config}}, socket) do
    agent = Agents.get_agent(socket.assigns.agent_id)    
    updated = %Opamp.Proto.EffectiveConfig{
      config_map: %Opamp.Proto.AgentConfigMap{
        config_map: %{
          socket.assigns.collector => %Opamp.Proto.AgentConfigFile{
            body: new_config
          }
        },
      }
    }
    case Agents.update_agent(agent, %{effective_config: updated}) do
      {:ok, _agent} -> {:noreply, socket
                          |> put_flash(:info, "Updated. Running…")}
      {:error, _error} ->  {:noreply, socket
                          |> put_flash(:error, "failed!")}
        
    end
    
  end

  defp page_title(:show), do: "Show Agent"
  defp page_title(:edit), do: "Edit Agent"

  defp set_flash(socket, remote_config_status) when remote_config_status.last_remote_config_hash != socket.assigns.last_remote_config_hash do
    IO.inspect remote_config_status
    case remote_config_status.status do
      :RemoteConfigStatuses_UNSET ->
        put_flash(socket, :info, remote_config_status.error_message)
      :RemoteConfigStatuses_APPLIED ->
        socket
        |> assign(:config_hash, remote_config_status.last_remote_config_hash)
        |> put_flash(:info, "Success applying!")
      :RemoteConfigStatuses_APPLYING ->
        put_flash(socket, :info, "applying...")
      :RemoteConfigStatuses_FAILED ->
        put_flash(socket, :error, remote_config_status.error_message)
    end
  end
  defp set_flash(socket, _remote_config_status), do: socket

  defp assign_initial_changeset(socket, agent) do
    # Assign a changeset to the most recent snippet, if one exists, or a new snippet.
  
    changeset = Agents.Agent.changeset(agent, %{})

    socket 
    |> assign(changeset: changeset)
    |> assign(config_hash: agent.remote_config_status.last_remote_config_hash)
    |> assign(form: Phoenix.Component.to_form(changeset))
  end
end
