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
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def time_since(updated_datetime) do
    DateTime.utc_now()
    |> DateTime.diff(DateTime.from_unix!(updated_datetime, :nanosecond))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Agent")
    |> assign(:agent, Agents.get_agent!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Agent")
    |> assign(:agent, %Agent{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Agent")
    |> assign(:agent, nil)
  end

  @impl true
  def handle_info({OpAMPServerWeb.AgentLive.FormComponent, {:saved, agent}}, socket) do
    {:noreply, stream_insert(socket, :agent_collection, agent)}
  end

  @impl true
  def handle_info({:agent_created, agent}, socket) do
    new_agent = Agents.get_agent!(agent.id)
    {:noreply, stream_insert(socket, :agent_collection, new_agent)}
  end

  @impl true
  def handle_info({:agent_updated, agent}, socket) do
    {:noreply, socket |> stream_delete(:agent_collection, agent) |> stream_insert(:agent_collection, agent, reset: true)}
  end

  @impl true
  def handle_info({:agent_deleted, agent}, socket) do
    {:noreply, stream_delete(socket, :agent_collection, agent)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    agent = Agents.get_agent(id)
    {:ok, _} = Agents.delete_agent(agent)

    {:noreply, stream_delete(socket, :agent_collection, agent)}
  end

  def render_time(last_heartbeat) do
    DateTime.from_unix!(last_heartbeat, :nanosecond)
    |> Calendar.strftime("%I:%M:%S %p")
  end

  def find_description_field(description, field) do
    Enum.concat(description.identifying_attributes, description.non_identifying_attributes)
    |> Enum.find(fn kv -> kv.key == field end)
    |> get_value
  end

 defp get_value(nil), do: ""
 defp get_value(kv) do
  case kv.value.value do
    {:string_value, v} -> v
    {other, _v} ->
      IO.puts "unable to retrieve value for type #{other}"
      ""
  end
 end

end
