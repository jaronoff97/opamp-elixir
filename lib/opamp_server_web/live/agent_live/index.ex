defmodule OpAMPServerWeb.AgentLive.Index do
  @moduledoc "The list of connected agents, with a filter."
  use OpAMPServerWeb, :live_view

  alias OpAMPServer.Agents
  alias OpAMPServerWeb.AgentView

  # Refreshes the "last seen" times.
  @tick :timer.seconds(10)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Agents.subscribe()
      :timer.send_interval(@tick, :tick)
    end

    {:ok,
     assign(socket,
       page_title: "Agents",
       query: "",
       now: DateTime.utc_now(),
       agents: Map.new(Agents.list_agent(), &{&1.id, &1})
     )}
  end

  @impl true
  def handle_info({event, agent}, socket) when event in [:agent_created, :agent_updated] do
    {:noreply, update(socket, :agents, &Map.put(&1, agent.id, agent))}
  end

  def handle_info({:agent_deleted, agent}, socket) do
    {:noreply, update(socket, :agents, &Map.delete(&1, agent.id))}
  end

  def handle_info(:tick, socket), do: {:noreply, assign(socket, :now, DateTime.utc_now())}

  @impl true
  def handle_event("filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    # The agent can disconnect, which deletes it, after the page rendered its row.
    case Agents.get_agent(id) do
      nil -> :ok
      agent -> {:ok, _} = Agents.delete_agent(agent)
    end

    {:noreply, update(socket, :agents, &Map.delete(&1, id))}
  end

  @doc "The agents whose name, host or instance uid contains the query, sorted by name."
  def filter(agents, query) do
    query = query |> String.trim() |> String.downcase()

    agents
    |> Map.values()
    |> Enum.filter(fn agent ->
      query == "" or
        Enum.any?(
          [AgentView.name(agent), AgentView.attribute(agent, "host.name"), agent.id],
          &(&1 && String.contains?(String.downcase(&1), query))
        )
    end)
    |> Enum.sort_by(&{AgentView.name(&1), &1.id})
  end

  # An agent reports its config only with the ReportsEffectiveConfig capability.
  def collector_count(agent), do: agent |> AgentView.config_objects() |> length()
end
