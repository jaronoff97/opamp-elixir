defmodule OpAMPServerWeb.AgentLive.Show do
  use OpAMPServerWeb, :live_view
  import Phoenix.HTML.Form

  alias OpAMPServer.Agents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Agents.get_agent(id) do
      nil ->
        {:ok, redirect(socket, to: ~p"/")}

      agent ->
        if connected?(socket), do: OpAMPServer.Agents.subscribe_to_agent(id)

        {:ok,
         socket
         |> assign_initial_changeset(agent)
         |> assign(:agent_id, id)}
    end
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    agent = id |> Agents.get_agent!() |> with_defaults()
    map_keys = get_config_map_keys(agent)

    {:noreply,
     socket
     |> assign(:page_title, "Showing Agent")
     |> assign(:agent, agent)
     |> assign(map_keys: map_keys)}
  end

  defp get_config_map_keys(agent), do: Map.keys(agent.effective_config.config_map.config_map)

  # An agent reports health and config only with the matching capabilities, so either can be
  # missing. Empty defaults let the template read them without checks.
  defp with_defaults(agent) do
    config_map =
      case agent.effective_config do
        %{config_map: %Opamp.Proto.AgentConfigMap{} = config_map} -> config_map
        _ -> %Opamp.Proto.AgentConfigMap{}
      end

    %{
      agent
      | component_health: agent.component_health || %Opamp.Proto.ComponentHealth{},
        effective_config: %Opamp.Proto.EffectiveConfig{config_map: config_map}
    }
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
     |> update_agent_data(agent)}
  end

  @impl true
  def handle_info({:agent_superseded, _pid}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_deleted, _agent}, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
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
      {:noreply, assign(socket, :collector, collector)}
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

    remote_config =
      agent
      |> Agents.config_map_with(socket.assigns.collector, new_config)
      |> Agents.generate_desired_remote_config()

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

  defp set_flash(socket, %{remote_config_status: nil}), do: socket

  defp set_flash(socket, agent) do
    if agent.remote_config_status.last_remote_config_hash != socket.assigns.config_hash do
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
    else
      socket
    end
  end

  defp update_agent_data(socket, agent) do
    # Update agent data without resetting collector selection
    agent = with_defaults(agent)
    changeset = Agents.Agent.changeset(agent, %{})

    config_hash =
      if agent.remote_config_status,
        do: agent.remote_config_status.last_remote_config_hash,
        else: nil

    socket
    |> assign(changeset: changeset)
    |> assign(:agent, agent)
    |> assign(map_keys: get_config_map_keys(agent))
    |> assign(config_hash: config_hash)
    |> assign(form: Phoenix.Component.to_form(changeset))
  end

  defp assign_initial_changeset(socket, agent) do
    # Assign a changeset to the most recent snippet, if one exists, or a new snippet.
    agent = with_defaults(agent)
    changeset = Agents.Agent.changeset(agent, %{})

    config_hash =
      if agent.remote_config_status,
        do: agent.remote_config_status.last_remote_config_hash,
        else: nil

    socket
    |> assign(:collector, nil)
    |> push_event("reset", %{})
    |> assign(changeset: changeset)
    |> assign(:agent, agent)
    |> assign(config_hash: config_hash)
    |> assign(form: Phoenix.Component.to_form(changeset))
  end

  # The spec allows "" as a config key, for agents with a single config object.
  def config_key_label(""), do: "(default)"
  def config_key_label(key), do: key

  # 0 is the protobuf default: the agent has not reported the time.
  def render_time(time) when time in [nil, 0], do: ""

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

  # Read the pods from the current health on each render: a rollout replaces pods while the
  # page is open. A collector has no health entry until the agent reports one.
  def pods(agent, collector) do
    case agent.component_health do
      %{component_health_map: %{^collector => %{component_health_map: pods}}} -> Enum.sort(pods)
      _ -> []
    end
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

  def find_description_field(nil, _field), do: ""

  def find_description_field(description, field) do
    identifying = description.identifying_attributes || []
    non_identifying = description.non_identifying_attributes || []

    Enum.concat(identifying, non_identifying)
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
