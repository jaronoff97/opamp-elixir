defmodule OpAMPServerWeb.AgentLive.Show do
  use OpAMPServerWeb, :live_view

  alias OpAMPServer.Agents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign_initial_changeset(id)
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:agent, Agents.get_agent!(id))}
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
