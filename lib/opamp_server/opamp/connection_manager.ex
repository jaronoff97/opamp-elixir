defmodule OpAMPServer.OpAMP.ConnectionManager do
  @moduledoc """
  Manages OpAMP agent connection state.

  Tracks which agents are currently connected and provides connection
  lifecycle management. This is isolated from the transport layer.
  """

  use GenServer

  @name __MODULE__

  # Client API

  @doc """
  Starts the connection manager.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Check if this is a new connection (agent not currently tracked).
  """
  def is_new_connection?(agent_id, name \\ @name) do
    GenServer.call(name, {:is_new?, agent_id})
  end

  @doc """
  Register a new agent connection.
  """
  def register(agent_id, name \\ @name) do
    GenServer.call(name, {:register, agent_id})
  end

  @doc """
  Unregister an agent connection (on disconnect).
  """
  def unregister(agent_id, name \\ @name) do
    GenServer.cast(name, {:unregister, agent_id})
  end

  @doc """
  Check if an agent is currently connected.
  """
  def connected?(agent_id, name \\ @name) do
    GenServer.call(name, {:connected?, agent_id})
  end

  @doc """
  Get the list of all connected agent IDs.
  """
  def list_connections(name \\ @name) do
    GenServer.call(name, :list)
  end

  @doc """
  Get the count of connected agents.
  """
  def connection_count(name \\ @name) do
    GenServer.call(name, :count)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{connections: MapSet.new()}}
  end

  @impl true
  def handle_call({:is_new?, agent_id}, _from, state) do
    is_new = not MapSet.member?(state.connections, agent_id)
    {:reply, is_new, state}
  end

  @impl true
  def handle_call({:register, agent_id}, _from, state) do
    new_connections = MapSet.put(state.connections, agent_id)
    {:reply, :ok, %{state | connections: new_connections}}
  end

  @impl true
  def handle_call({:connected?, agent_id}, _from, state) do
    {:reply, MapSet.member?(state.connections, agent_id), state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, MapSet.to_list(state.connections), state}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, MapSet.size(state.connections), state}
  end

  @impl true
  def handle_cast({:unregister, agent_id}, state) do
    new_connections = MapSet.delete(state.connections, agent_id)
    {:noreply, %{state | connections: new_connections}}
  end
end
