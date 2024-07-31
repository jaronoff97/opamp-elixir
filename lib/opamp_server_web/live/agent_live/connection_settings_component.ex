defmodule OpAMPServerWeb.AgentLive.ConnectionSettingsComponent do
  use OpAMPServerWeb, :live_component

  alias OpAMPServer.Agents

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>
          Use this form to update telemetry settings. Right now, headers cannot be added.
        </:subtitle>
      </.header>

      <.simple_form
        for={@settings}
        id="telemetry-settings-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@settings[:destination_endpoint]} type="text" label="Destination Endpoint" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Agent</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    settings = %{
      destination_endpoint: "",
      headers: []
    }

    types = %{destination_endpoint: :string, headers: :array}

    settings_changes =
      {settings, types}
      |> Ecto.Changeset.cast(%{}, Map.keys(types))

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(settings_changes)}
  end

  @impl true
  def handle_event("validate", %{"settings" => settings_params}, socket) do
    changeset =
      socket.assigns.agent
      |> Agents.change_agent(%{:connection_settings => settings_params})
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"settings" => settings_params}, socket) do
    save_settings(socket, socket.assigns.action, settings_params)
  end

  @impl true
  def handle_event("add_header", _, socket) do
    headers = socket.assigns.settings.data.headers
    new_headers = headers ++ [{"key", "value"}]

    settings_changes =
      socket.assigns.settings
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:headers, new_headers)

    {:noreply, assign_form(socket, settings_changes)}
  end

  defp save_settings(socket, :edit_connection, settings_params) do
    case Agents.update_agent(socket.assigns.agent, %{
           connection_settings: generate_connection_settings(settings_params)
         }) do
      {:ok, settings} ->
        notify_parent({:saved, settings})

        {:noreply,
         socket
         |> put_flash(:info, "Settings updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :settings, to_form(changeset, as: :settings))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp generate_connection_settings(%{"destination_endpoint" => endpoint} = _params) do
    %Opamp.Proto.ConnectionSettingsOffers{
      own_metrics: %Opamp.Proto.TelemetryConnectionSettings{
        destination_endpoint: endpoint
      },
      own_traces: %Opamp.Proto.TelemetryConnectionSettings{
        destination_endpoint: endpoint
      },
      own_logs: %Opamp.Proto.TelemetryConnectionSettings{
        destination_endpoint: endpoint
      }
    }
  end
end
