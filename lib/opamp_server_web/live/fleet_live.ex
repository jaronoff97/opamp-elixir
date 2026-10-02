defmodule OpAMPServerWeb.FleetLive do
  @moduledoc """
  The fleet: a graph of this server, every connected agent and the collectors that each
  OpAMP Bridge manages. A click on a node shows its details beside the graph.
  """
  use OpAMPServerWeb, :live_view

  alias OpAMPServer.Agents
  alias OpAMPServerWeb.{AgentView, Graph}
  alias OpAMPServerWeb.Graph.Fleet

  # Refreshes the "last seen" times.
  @tick :timer.seconds(10)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Agents.subscribe()
      :timer.send_interval(@tick, :tick)
    end

    {:ok,
     socket
     |> assign(page_title: "Fleet", selected: nil, now: DateTime.utc_now())
     |> assign_agents(Map.new(Agents.list_agent(), &{&1.id, &1}))}
  end

  @impl true
  def handle_info({event, agent}, socket) when event in [:agent_created, :agent_updated] do
    {:noreply, assign_agents(socket, Map.put(socket.assigns.agents, agent.id, agent))}
  end

  def handle_info({:agent_deleted, agent}, socket) do
    {:noreply, assign_agents(socket, Map.delete(socket.assigns.agents, agent.id))}
  end

  def handle_info(:tick, socket), do: {:noreply, assign(socket, :now, DateTime.utc_now())}

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected, if(socket.assigns.selected == id, do: nil, else: id))}
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, :selected, nil)}

  defp assign_agents(socket, agents) do
    graph = Fleet.build(Map.values(agents))
    # A selected node goes away when its agent disconnects.
    selected =
      socket.assigns[:selected] && Graph.node(graph, socket.assigns.selected) &&
        socket.assigns.selected

    assign(socket, agents: agents, graph: graph, selected: selected)
  end

  defp stats(agents) do
    agents = Map.values(agents)

    collectors =
      Enum.flat_map(agents, &Enum.filter(AgentView.config_objects(&1), fn o -> o.resource? end))

    %{
      agents: length(agents),
      healthy: Enum.count(agents, &(AgentView.status(&1) == :healthy)),
      collectors: length(collectors),
      attention:
        Enum.count(agents, fn agent ->
          AgentView.status(agent) == :unhealthy or
            elem(AgentView.remote_config(agent), 0) == :failed
        end)
    }
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :stats, stats(assigns.agents))

    ~H"""
    <Layouts.app flash={@flash} current={:fleet}>
      <.header>
        Fleet
        <:subtitle>
          Every agent connected to this server, and the collectors that each one manages.
        </:subtitle>
      </.header>

      <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <.stat_card label="Connected agents" value={@stats.agents} icon="hero-server-stack" />
        <.stat_card label="Healthy" value={@stats.healthy} icon="hero-heart" tone="text-success" />
        <.stat_card label="Collectors" value={@stats.collectors} icon="hero-cube" tone="text-accent" />
        <.stat_card
          label="Need attention"
          value={@stats.attention}
          icon="hero-exclamation-triangle"
          tone={if @stats.attention > 0, do: "text-error", else: "text-base-content/40"}
        />
      </div>

      <div :if={@agents == %{}} role="status" class="alert alert-info alert-soft mt-6">
        <.icon name="hero-information-circle" class="size-5" />
        <span>
          No agents are connected. Point an OpAMP agent at <code class="font-mono">{opamp_url()}</code>.
        </span>
      </div>

      <div class="mt-6 flex flex-col gap-4 xl:flex-row">
        <.graph
          id="fleet"
          graph={@graph}
          selected={@selected}
          on_select="select"
          class="h-[calc(100vh-18rem)] min-h-96 flex-1"
        >
          <:node :let={node}><.fleet_node node={node} now={@now} /></:node>
        </.graph>

        <.details :if={@selected} node={Graph.node(@graph, @selected)} agents={@agents} now={@now} />
      </div>
    </Layouts.app>
    """
  end

  defp opamp_url,
    do: String.replace_prefix(OpAMPServerWeb.Endpoint.url(), "http", "ws") <> "/v1/opamp"

  attr :node, Graph.Node, required: true
  attr :now, DateTime, required: true

  defp fleet_node(%{node: %{type: :server}} = assigns) do
    ~H"""
    <div class="flex size-full items-center gap-3 rounded-box border border-primary/40 bg-primary/10 px-4">
      <img src={~p"/images/otel.svg"} width="28" alt="" />
      <div class="min-w-0">
        <div class="text-sm font-semibold">opamp-elixir</div>
        <div class="text-xs text-base-content/60">
          {@node.data.agents} {if @node.data.agents == 1, do: "agent", else: "agents"}
        </div>
      </div>
    </div>
    """
  end

  defp fleet_node(%{node: %{type: :agent, data: agent}} = assigns) do
    assigns =
      assign(assigns,
        agent: agent,
        collectors: Enum.count(AgentView.config_objects(agent), & &1.resource?),
        subtitle:
          Enum.reject(
            [
              AgentView.attribute(agent, "host.name"),
              AgentView.attribute(agent, "service.version")
            ],
            &is_nil/1
          )
      )

    ~H"""
    <div class="flex size-full flex-col justify-center gap-1 rounded-box border border-base-300 bg-base-100 px-4 shadow-xs transition-colors hover:border-primary/50">
      <div class="flex items-center gap-2">
        <.status_dot status={AgentView.status(@agent)} />
        <span class="truncate text-sm font-semibold" title={AgentView.name(@agent)}>
          {AgentView.name(@agent)}
        </span>
        <span
          :if={AgentView.kind(@agent) == :bridge}
          class="badge badge-xs badge-soft badge-primary ml-auto"
        >
          bridge
        </span>
      </div>
      <div class="truncate text-xs text-base-content/60">
        {if @subtitle == [], do: @agent.id, else: Enum.join(@subtitle, " · ")}
      </div>
      <div class="flex items-center gap-1.5 text-xs text-base-content/60">
        <span :if={@collectors > 0}>{@collectors} {if @collectors == 1,
          do: "collector",
          else: "collectors"} ·</span>
        <span>seen {AgentView.ago(@agent.updated_at, @now)}</span>
      </div>
    </div>
    """
  end

  defp fleet_node(%{node: %{type: :collector, data: object}} = assigns) do
    assigns = assign(assigns, object: object, pods: AgentView.pods(object.health))

    ~H"""
    <div class="flex size-full flex-col justify-center gap-1 rounded-box border border-base-300 bg-base-100 px-4 shadow-xs transition-colors hover:border-primary/50">
      <div class="flex items-center gap-2">
        <.icon name="hero-cube" class="size-4 shrink-0 text-accent" />
        <span class="truncate text-sm font-medium">{@object.key}</span>
      </div>
      <div class="flex items-center gap-2 text-xs text-base-content/60">
        <span>{elem(@pods, 0)}/{elem(@pods, 1)} pods ready</span>
        <span class={[
          "badge badge-xs badge-soft",
          if(@object.managed?, do: "badge-success", else: "badge-ghost")
        ]}>
          {if @object.managed?, do: "managed", else: "read-only"}
        </span>
      </div>
    </div>
    """
  end

  attr :node, Graph.Node, required: true
  attr :agents, :map, required: true
  attr :now, DateTime, required: true

  defp details(assigns) do
    ~H"""
    <aside id="fleet-details" class="card card-border w-full shrink-0 bg-base-100 xl:w-80">
      <div class="card-body gap-4 p-5">
        <div class="flex items-start justify-between gap-2">
          <h2 class="text-sm font-semibold">{details_title(@node)}</h2>
          <button
            type="button"
            phx-click="close"
            class="btn btn-ghost btn-xs btn-square"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
        <.details_body node={@node} agents={@agents} now={@now} />
      </div>
    </aside>
    """
  end

  defp details_title(%{type: :server}), do: "This server"
  defp details_title(%{type: :agent, data: agent}), do: AgentView.name(agent)
  defp details_title(%{type: :collector, data: object}), do: object.key

  defp details_body(%{node: %{type: :server}} = assigns) do
    ~H"""
    <.kv_list items={[{"OpAMP endpoint", opamp_url()}, {"Agents", map_size(@agents)}]} />
    <.link navigate={~p"/settings"} class="btn btn-sm btn-outline">
      <.icon name="hero-cog-6-tooth" class="size-4" /> Server settings
    </.link>
    """
  end

  defp details_body(%{node: %{type: :agent, data: agent}} = assigns) do
    assigns = assign(assigns, agent: agent, remote: AgentView.remote_config(agent))

    ~H"""
    <div class="flex flex-wrap gap-2">
      <.status_badge status={AgentView.status(@agent)} />
      <.status_badge status={elem(@remote, 0)} />
    </div>
    <p :if={AgentView.last_error(@agent)} class="text-sm text-error">
      {AgentView.last_error(@agent)}
    </p>
    <.kv_list items={[
      {"instance", @agent.id},
      {"version", AgentView.attribute(@agent, "service.version") || "—"},
      {"host", AgentView.attribute(@agent, "host.name") || "—"},
      {"last seen", AgentView.ago(@agent.updated_at, @now)}
    ]} />
    <.link navigate={~p"/agents/#{@agent.id}"} class="btn btn-sm btn-primary">
      Open agent <.icon name="hero-arrow-right" class="size-4" />
    </.link>
    """
  end

  defp details_body(%{node: %{type: :collector, data: object}} = assigns) do
    assigns = assign(assigns, object: object, pods: AgentView.pods(object.health))

    ~H"""
    <.kv_list items={[
      {"agent", AgentView.name(@agents[@object.agent_id])},
      {"pods ready", "#{elem(@pods, 0)} of #{elem(@pods, 1)}"},
      {"management", if(@object.managed?, do: "managed by this server", else: "read-only")}
    ]} />
    <div class="flex flex-wrap gap-2">
      <.link
        navigate={~p"/agents/#{@object.agent_id}/config?#{[object: @object.key]}"}
        class="btn btn-sm btn-primary"
      >
        <.icon name="hero-pencil-square" class="size-4" /> Config
      </.link>
      <.link
        navigate={~p"/agents/#{@object.agent_id}/pipeline?#{[object: @object.key]}"}
        class="btn btn-sm btn-outline"
      >
        <.icon name="hero-arrows-right-left" class="size-4" /> Pipeline
      </.link>
    </div>
    """
  end
end
