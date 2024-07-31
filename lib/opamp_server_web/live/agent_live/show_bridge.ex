defmodule OpAMPServerWeb.AgentLive.ShowBridge do
  use OpAMPServerWeb, :live_view
  import Phoenix.HTML.Form

  alias OpAMPServer.Agents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Agents.get_agent(id) do
      nil ->
        {:ok, redirect(socket, to: ~p"/agent")}

      agent ->
        if connected?(socket), do: OpAMPServer.Agents.subscribe_to_agent(id)

        {:ok,
         socket
         |> assign_initial_changeset(agent)
         |> assign(:agent_id, id)
         |> assign(:collector, "")}
    end
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    agent = Agents.get_agent!(id)

    {:noreply,
     socket
     |> assign(:page_title, "Showing Agent")
     |> assign(:agent, agent)
     |> assign(map_keys: Map.keys(agent.effective_config.config_map.config_map))}
  end

  @impl true
  def handle_info({:agent_created, _agent}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_updated, agent}, socket) do
    {:noreply,
     socket
     |> set_flash(agent)
     |> assign_initial_changeset(agent)}
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
    if socket.assigns.collector == collector do
      {:noreply,
       socket
       |> assign(:collector, nil)
       |> push_event("reset", %{})}
    else
      {:noreply,
       socket
       |> assign_pods(collector)
       |> assign(:collector, collector)}
    end
  end

  @impl true
  def handle_event("select", %{"pod" => pod}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "clicked #{pod}")}
  end

  @impl true
  def handle_event("save", %{"agent" => %{"effective_config" => new_config}}, socket) do
    agent = Agents.get_agent(socket.assigns.agent_id)

    updated = %Opamp.Proto.AgentConfigMap{
      config_map: %{
        socket.assigns.collector => %Opamp.Proto.AgentConfigFile{
          body: new_config
        }
      }
    }

    remote_config = Agents.generate_desired_remote_config(updated)

    case Agents.update_agent(agent, %{desired_remote_config: remote_config}) do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> assign(:collector, nil)
         |> push_event("reset", %{})
         |> put_flash(:info, "Updated. Running…")}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, "failed!")}
    end
  end

  defp set_flash(socket, agent)
       when agent.remote_config_status.last_remote_config_hash != socket.assigns.config_hash do
    case agent.remote_config_status.status do
      :RemoteConfigStatuses_UNSET ->
        put_flash(socket, :info, agent.remote_config_status.error_message)

      :RemoteConfigStatuses_APPLIED ->
        socket
        |> put_flash(:info, "Success applying!")

      :RemoteConfigStatuses_APPLYING ->
        put_flash(socket, :info, "applying...")

      :RemoteConfigStatuses_FAILED ->
        put_flash(socket, :error, agent.remote_config_status.error_message)
    end
  end

  defp set_flash(socket, _remote_config_status), do: socket

  defp assign_initial_changeset(socket, agent) do
    # Assign a changeset to the most recent snippet, if one exists, or a new snippet.
    changeset = Agents.Agent.changeset(agent, %{})

    socket
    |> assign(:collector, nil)
    |> push_event("reset", %{})
    |> assign(changeset: changeset)
    |> assign(:agent, agent)
    |> assign(config_hash: agent.remote_config_status.last_remote_config_hash)
    |> assign(form: Phoenix.Component.to_form(changeset))
  end

  def render_time(nil), do: ""

  def render_time(last_heartbeat) do
    DateTime.from_unix!(last_heartbeat, :nanosecond)
    |> Calendar.strftime("%B %-d, %Y %I:%M:%S %p")
  end

  def managed?(nil, _collector), do: "❓"

  def managed?(agent = %{}, collector) do
    agent.effective_config.config_map.config_map[collector]
    |> get_effective_config_field(:body)
    |> contains_managed
  end

  defp assign_pods(socket, collector) do
    socket
    |> assign(
      :pod_map_keys,
      Map.keys(
        socket.assigns.agent.component_health.component_health_map[collector].component_health_map
      )
    )
  end

  defp contains_managed(nil), do: "❓"

  defp contains_managed(body) do
    case String.contains?(body, "opentelemetry.io/opamp-managed") do
      true -> "✅"
      _ -> "🚫"
    end
  end

  defp get_effective_config_field(nil, _field), do: nil

  defp get_effective_config_field(config_map, field) do
    Map.get(config_map, field, "")
  end

  def find_description_field(description, field) do
    Enum.concat(description.identifying_attributes, description.non_identifying_attributes)
    |> Enum.find(fn kv -> kv.key == field end)
    |> get_value
  end

  defp get_value(nil), do: ""

  defp get_value(kv) do
    case kv.value.value do
      {:string_value, v} ->
        v

      {other, _v} ->
        IO.puts("unable to retrieve value for type #{other}")
        ""
    end
  end
end
