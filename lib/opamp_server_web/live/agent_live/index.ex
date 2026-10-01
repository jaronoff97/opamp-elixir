defmodule OpAMPServerWeb.AgentLive.Index do
  use OpAMPServerWeb, :live_view

  alias OpAMPServer.Agents
  alias OpAMPServer.Agents.Agent

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Agents.subscribe()
    {:ok, stream(socket, :agent_collection, Agents.list_agent())}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Listing Agent")}
  end

  def time_since(updated_datetime) do
    DateTime.utc_now()
    |> DateTime.diff(DateTime.from_unix!(updated_datetime, :nanosecond))
  end

  @impl true
  def handle_info({:agent_created, agent}, socket) do
    new_agent = Agents.get_agent!(agent.id)
    {:noreply, stream_insert(socket, :agent_collection, new_agent)}
  end

  @impl true
  def handle_info({:agent_updated, agent}, socket) do
    {:noreply,
     socket
     |> stream_delete(:agent_collection, agent)
     |> stream_insert(:agent_collection, agent, reset: true)}
  end

  @impl true
  def handle_info({:agent_deleted, agent}, socket) do
    {:noreply, stream_delete(socket, :agent_collection, agent)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    # The agent can disconnect, which deletes it, after the page rendered its row.
    case Agents.get_agent(id) do
      nil -> :ok
      agent -> {:ok, _} = Agents.delete_agent(agent)
    end

    {:noreply, stream_delete(socket, :agent_collection, %Agent{id: id})}
  end

  # An agent reports its config only with the ReportsEffectiveConfig capability.
  def collector_count(%{effective_config: %{config_map: %{config_map: objects}}}),
    do: map_size(objects)

  def collector_count(_agent), do: 0

  def render_time(last_heartbeat) do
    DateTime.from_unix!(last_heartbeat, :nanosecond)
    |> Calendar.strftime("%I:%M:%S %p")
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
