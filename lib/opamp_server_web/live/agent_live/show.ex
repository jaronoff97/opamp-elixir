defmodule OpAMPServerWeb.AgentLive.Show do
  use OpAMPServerWeb, :live_view
  import Phoenix.HTML.Form

  alias OpAMPServer.Agents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign_initial_changeset(id)
      |> assign(:collector, "")
    {:ok, socket}
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
  def handle_event("validate", %{"agent" => _changed}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select", %{"collector" => collector}, socket) do
    {:noreply, socket
      |> assign(:collector, collector)}
  end 

  defp page_title(:show), do: "Show Agent"
  defp page_title(:edit), do: "Edit Agent"


  defp assign_initial_changeset(socket, id) do
    # Assign a changeset to the most recent snippet, if one exists, or a new snippet.
  
    changeset = Agents.get_agent!(id)
      |> Agents.Agent.changeset(%{})

    socket 
    |> assign(changeset: changeset)
    |> assign(form: Phoenix.Component.to_form(changeset))
  end
end
