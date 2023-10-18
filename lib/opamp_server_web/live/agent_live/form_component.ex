defmodule OpAMPServerWeb.AgentLive.FormComponent do
  use OpAMPServerWeb, :live_component

  alias OpAMPServer.Agents

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage agent records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="agent-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:instance_id]} type="text" label="Instance" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Agent</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{agent: agent} = assigns, socket) do
    changeset = Agents.change_agent(agent)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"agent" => agent_params}, socket) do
    changeset =
      socket.assigns.agent
      |> Agents.change_agent(agent_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"agent" => agent_params}, socket) do
    save_agent(socket, socket.assigns.action, agent_params)
  end

  defp save_agent(socket, :edit, agent_params) do
    case Agents.update_agent(socket.assigns.agent, agent_params) do
      {:ok, agent} ->
        notify_parent({:saved, agent})

        {:noreply,
         socket
         |> put_flash(:info, "Agent updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_agent(socket, :new, agent_params) do
    case Agents.create_agent(agent_params) do
      {:ok, agent} ->
        notify_parent({:saved, agent})

        {:noreply,
         socket
         |> put_flash(:info, "Agent created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
