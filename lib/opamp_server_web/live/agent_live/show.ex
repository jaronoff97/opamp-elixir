defmodule OpAMPServerWeb.AgentLive.Show do
  @moduledoc """
  One agent, in four tabs: overview, config (edit and send a remote config), pipeline
  (a graph of the selected collector config) and connection (connection settings and
  the client certificate). The `object` query parameter selects a config object.
  """
  use OpAMPServerWeb, :live_view

  alias OpAMPServer.{Agents, CollectorConfig}
  alias OpAMPServer.OpAMP.ConnectionSettings
  alias OpAMPServerWeb.{AgentView, Graph}
  alias OpAMPServerWeb.Graph.Pipeline

  # Refreshes the "last seen" time.
  @tick :timer.seconds(10)

  @tabs [overview: "Overview", config: "Config", pipeline: "Pipeline", connection: "Connection"]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Agents.get_agent(id) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "That agent is not connected.") |> redirect(to: ~p"/agents")}

      agent ->
        if connected?(socket) do
          Agents.subscribe_to_agent(id)
          :timer.send_interval(@tick, :tick)
        end

        {:ok,
         socket
         |> assign(
           tabs: @tabs,
           now: DateTime.utc_now(),
           object_key: nil,
           component: nil,
           certificate: Agents.get_certificate(id)
         )
         |> assign_agent(agent)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    objects = socket.assigns.objects

    key =
      if Enum.any?(objects, &(&1.key == params["object"])),
        do: params["object"],
        else: default_object(objects, socket.assigns.live_action)

    {:noreply,
     socket
     |> assign(
       page_title:
         "#{AgentView.name(socket.assigns.agent)} · #{@tabs[socket.assigns.live_action]}",
       object_key: key,
       component: nil
     )
     |> assign_pipeline()}
  end

  # The pipeline tab opens the first object that has pipelines.
  defp default_object(objects, :pipeline) do
    Enum.find_value(objects, fn object ->
      object.config && CollectorConfig.pipelines(object.config) != [] && object.key
    end) || default_object(objects, :config)
  end

  defp default_object([first | _], _action), do: first.key
  defp default_object([], _action), do: nil

  defp assign_agent(socket, agent) do
    objects = AgentView.config_objects(agent)
    key = socket.assigns.object_key

    # The selected object can go away when the agent reports a new config.
    key =
      if Enum.any?(objects, &(&1.key == key)),
        do: key,
        else: default_object(objects, socket.assigns[:live_action])

    assign(socket,
      agent: agent,
      objects: objects,
      object_key: key,
      config_hash:
        agent.remote_config_status && agent.remote_config_status.last_remote_config_hash
    )
  end

  defp assign_pipeline(socket) do
    pipeline =
      case selected_object(socket.assigns) do
        %{config: %CollectorConfig{} = config} -> Pipeline.build(config)
        _ -> Graph.new()
      end

    assign(socket, :pipeline, pipeline)
  end

  defp selected_object(%{objects: objects, object_key: key}),
    do: Enum.find(objects, &(&1.key == key))

  @impl true
  def handle_info({:agent_updated, agent}, socket) do
    {:noreply, socket |> set_flash(agent) |> assign_agent(agent) |> assign_pipeline()}
  end

  def handle_info({:agent_deleted, _agent}, socket) do
    {:noreply,
     socket |> put_flash(:info, "The agent disconnected.") |> push_navigate(to: ~p"/agents")}
  end

  def handle_info({event, _}, socket) when event in [:agent_created, :agent_superseded],
    do: {:noreply, socket}

  def handle_info(:tick, socket), do: {:noreply, assign(socket, :now, DateTime.utc_now())}

  @impl true
  def handle_event("select_component", %{"id" => id}, socket) do
    {:noreply, assign(socket, :component, if(socket.assigns.component == id, do: nil, else: id))}
  end

  def handle_event("save", %{"config" => %{"body" => body}}, socket) do
    agent = Agents.get_agent(socket.assigns.agent.id)

    remote_config =
      agent
      |> Agents.config_map_with(socket.assigns.object_key, body)
      |> Agents.generate_desired_remote_config()

    case Agents.update_agent(agent, %{desired_remote_config: remote_config}) do
      {:ok, _agent} -> {:noreply, put_flash(socket, :info, "Sent the new config to the agent.")}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "Could not save the config.")}
    end
  end

  # A flash for each new remote config status that the agent reports.
  defp set_flash(socket, %{remote_config_status: nil}), do: socket

  defp set_flash(socket, %{remote_config_status: status}) do
    if status.last_remote_config_hash == socket.assigns.config_hash do
      socket
    else
      case status.status do
        :RemoteConfigStatuses_APPLIED ->
          put_flash(socket, :info, "The agent applied the config.")

        :RemoteConfigStatuses_APPLYING ->
          put_flash(socket, :info, "The agent is applying the config…")

        :RemoteConfigStatuses_FAILED ->
          put_flash(socket, :error, status.error_message)

        _ ->
          socket
      end
    end
  end

  defp tab_path(agent, :overview, _key), do: ~p"/agents/#{agent.id}"
  defp tab_path(agent, action, nil), do: "/agents/#{agent.id}/#{action}"

  defp tab_path(agent, action, key),
    do: "/agents/#{agent.id}/#{action}?" <> URI.encode_query(object: key)

  # The spec allows "" as a config key, for agents with a single config object.
  def config_key_label(""), do: "(default)"
  def config_key_label(key), do: key

  # 0 is the protobuf default: the agent has not reported the time.
  def render_time(time) when time in [nil, 0], do: "—"

  def render_time(nanos) do
    nanos |> DateTime.from_unix!(:nanosecond) |> Calendar.strftime("%b %-d, %Y %H:%M:%S UTC")
  end

  # A compact time for tables, without the year.
  def short_time(time) when time in [nil, 0], do: "—"

  def short_time(nanos) do
    nanos |> DateTime.from_unix!(:nanosecond) |> Calendar.strftime("%b %-d %H:%M")
  end

  def pods(%{component_health_map: pods}), do: Enum.sort(pods)
  def pods(_health), do: []

  # The config of one pipeline component, as JSON.
  defp component_config(object, %Graph.Node{data: %{kind: kind, name: name}}) do
    section =
      case kind do
        :receiver -> "receivers"
        :processor -> "processors"
        :exporter -> "exporters"
        :connector -> "connectors"
      end

    case object.config.config[section] do
      %{^name => config} -> Jason.encode!(config || %{}, pretty: true)
      _ -> "{}"
    end
  end

  @kind_style %{
    receiver: {"Receiver", "border-l-info", "bg-info"},
    processor: {"Processor", "border-l-accent", "bg-accent"},
    exporter: {"Exporter", "border-l-success", "bg-success"},
    connector: {"Connector", "border-l-secondary", "bg-secondary"}
  }

  @signal_style %{"traces" => "bg-info", "metrics" => "bg-accent", "logs" => "bg-success"}

  attr :node, Graph.Node, required: true

  defp pipeline_node(assigns) do
    {label, border, _dot} = @kind_style[assigns.node.data.kind]
    assigns = assign(assigns, label: label, border: border, signal_style: @signal_style)

    ~H"""
    <div class={[
      "flex size-full flex-col justify-center gap-1 rounded-box border border-base-300 border-l-4 bg-base-100 px-3 shadow-xs",
      @border
    ]}>
      <span class="truncate font-mono text-sm">{@node.data.name}</span>
      <span class="flex items-center gap-2 text-xs text-base-content/60">
        {@label}
        <span :for={signal <- @node.data.signals} class="flex items-center gap-1">
          <span class={["size-1.5 rounded-full", @signal_style[signal] || "bg-base-content/40"]} />{signal}
        </span>
      </span>
    </div>
    """
  end

  defp legend(assigns) do
    assigns = assign(assigns, kinds: Map.values(@kind_style), signals: @signal_style)

    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-base-content/60">
      <span :for={{label, _border, dot} <- Enum.sort(@kinds)} class="flex items-center gap-1.5">
        <span class={["size-2.5 rounded-sm", dot]} />{label}
      </span>
      <span class="mx-1 h-3 border-l border-base-300" />
      <span :for={{signal, dot} <- Enum.sort(@signals)} class="flex items-center gap-1.5">
        <span class={["size-1.5 rounded-full", dot]} />{signal}
      </span>
    </div>
    """
  end

  attr :objects, :list, required: true
  attr :selected, :string, default: nil
  attr :agent, :map, required: true
  attr :action, :atom, required: true

  defp object_menu(assigns) do
    ~H"""
    <nav aria-label="Config objects">
      <ul class="menu w-full rounded-box border border-base-300 bg-base-100">
        <li class="menu-title">Config objects</li>
        <li :for={object <- @objects}>
          <.link
            patch={tab_path(@agent, @action, object.key)}
            class={[object.key == @selected && "menu-active"]}
            aria-current={if object.key == @selected, do: "true", else: "false"}
          >
            <.icon
              name={if object.resource?, do: "hero-cube", else: "hero-document-text"}
              class="size-4"
            />
            <span class="truncate">{config_key_label(object.key)}</span>
            <span :if={not object.managed?} class="badge badge-xs badge-ghost ml-auto">read-only</span>
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  @connection_capabilities ~w(AcceptsOpAMPConnectionSettings AcceptsOtherConnectionSettings
    ReportsOwnMetrics ReportsOwnTraces ReportsOwnLogs ReportsConnectionSettingsStatus)

  defp connection_capabilities(agent) do
    reported = AgentView.capabilities(agent)
    for name <- @connection_capabilities, do: {name, name in reported}
  end
end
