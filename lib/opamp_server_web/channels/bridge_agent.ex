defmodule OpAMPServerWeb.BridgeAgent do
  use Agent
  import Bitwise

  @doc """
  Starts a bridge agent.
  """
  def start_link(agent_id, _opts) do
    Agent.start_link(fn -> %{
        agent_id: %{}
      } end, name: :opampagent)
    %Opamp.Proto.ServerToAgent{
      instance_uid: agent_id,
      capabilities: server_capabilities()
    }
  end

  def server_capabilities do
    [
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsStatus,
      Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersRemoteConfig,
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsEffectiveConfig,
      Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersConnectionSettings,
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsConnectionSettingsRequest
    ]
    |> Enum.map(fn c -> server_capability_to_int(c) end)
    |> Enum.reduce(fn c, acc -> bor(c, acc) end)
  end

  def server_capability_to_int(capability) do
    case capability do
      Opamp.Proto.ServerCapabilities.ServerCapabilities_Unspecified ->
        0
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsStatus ->
        1
      Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersRemoteConfig ->
        2
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsEffectiveConfig ->
        4
      Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersPackages ->
        8
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsPackagesStatus ->
        10
      Opamp.Proto.ServerCapabilities.ServerCapabilities_OffersConnectionSettings ->
        20
      Opamp.Proto.ServerCapabilities.ServerCapabilities_AcceptsConnectionSettingsRequest ->
        40
      _ ->
        0
    end
  end

  @doc """
  Gets a value from the `agent_map` by `agent_id`.
  """
  def get(agent_map, agent_id) do
    Agent.get(agent_map, &Map.get(&1, agent_id))
  end

  @doc """
  Puts the `value` for the given `agent_id` in the `agent_map`.
  """
  def put(agent_map, agent_id, effective_config) do
    case OpAMPServer.Agents.get_agent(agent_id) do
      nil ->
        OpAMPServer.Agents.create_agent(%{id: agent_id, effective_config: effective_config})
      agent ->
        OpAMPServer.Agents.update_agent(agent, %{effective_config: effective_config})
    end
    Agent.update(agent_map, &Map.put(&1, agent_id, effective_config))
  end

  @doc """
  Puts the `value` for the given `agent_id` in the `agent_map`.
  """
  def delete(agent_map, agent_id) do
    case OpAMPServer.Agents.get_agent(agent_id) do
      nil ->
        {:error, "not found"}
      agent ->
        Agent.update(agent_map, &Map.delete(&1, agent_id))
        OpAMPServerWeb.Serializer.remove(agent_id)
        OpAMPServer.Agents.delete_agent(agent)
    end

  end
end