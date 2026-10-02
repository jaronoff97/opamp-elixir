defmodule OpAMPServerWeb.AgentsChannel do
  @moduledoc """
  Phoenix Channel for handling OpAMP agent connections.

  This channel handles the Phoenix-specific aspects of agent communication,
  delegating protocol logic to the OpAMP.Protocol layer.
  """

  use OpAMPServerWeb, :channel

  alias OpAMPServer.OpAMP.ConnectionSettings
  alias OpAMPServer.OpAMP.Protocol.Helpers
  require Logger

  @max_message_size Application.compile_env!(:opamp_server, :max_message_size)

  @report_full_state Helpers.server_flags_to_int(
                       Opamp.Proto.ServerToAgentFlags.ServerToAgentFlags_ReportFullState
                     )

  # Agent fields the server expects, keyed by the capability that promises them.
  @reported_state [
    description: Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsStatus,
    effective_config: Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsEffectiveConfig,
    remote_config_status: Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsRemoteConfig,
    component_health: Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsHealth
  ]

  # The channel is already subscribed to its own "agents:<id>" topic, which is
  # where OpAMPServer.Agents broadcasts updates for this agent.
  @impl true
  def join("agents:" <> agent_id, payload, socket) do
    socket =
      assign(socket,
        agent_id: agent_id,
        capabilities: payload.capabilities,
        sequence_num: payload.sequence_num,
        certificate: OpAMPServer.Agents.get_certificate(agent_id)
      )

    # An older connection of this agent can still be open, for example a half-open socket.
    # Tell its channel to stop, so that its terminate/2 does not delete the agent.
    Phoenix.PubSub.broadcast_from(
      OpAMPServer.PubSub,
      self(),
      "agents:" <> agent_id,
      {:agent_superseded, self()}
    )

    case create_or_update(agent_id, payload) do
      {:ok, agent} ->
        # ponytail: checked at join only; re-checking every message loops if an agent never sends a field
        flags = if missing_reported_state?(agent, payload), do: @report_full_state, else: 0

        {response, socket} = with_connection_settings(response(agent_id, flags), payload, socket)
        {response, socket} = with_pending_remote_config(response, agent, socket)
        {:ok, response, socket}

      {:error, _changeset} = error ->
        {:ok, generate_error_response(error), socket}
    end
  end

  @impl true
  def handle_info({:agent_created, _payload}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_deleted, _payload}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_superseded, _pid}, socket) do
    {:stop, {:shutdown, :superseded}, socket}
  end

  @impl true
  def handle_info({:agent_updated, agent}, socket) do
    case with_pending_remote_config(response(socket.assigns.agent_id), agent, socket) do
      {%{remote_config: nil}, socket} ->
        {:noreply, socket}

      {server_to_agent, socket} ->
        push(socket, "", server_to_agent)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, response(socket.assigns.agent_id)}, socket}
  end

  @impl true
  def handle_in("heartbeat", payload, socket) do
    # A gap in sequence numbers means the server missed a message, so its state may be stale.
    flags =
      if payload.sequence_num != socket.assigns.sequence_num + 1,
        do: @report_full_state,
        else: 0

    socket =
      assign(socket, capabilities: payload.capabilities, sequence_num: payload.sequence_num)

    {server_to_agent, socket} =
      with_connection_settings(response(socket.assigns.agent_id, flags), payload, socket)

    {server_to_agent, socket} =
      case create_or_update(socket.assigns.agent_id, payload) do
        {:ok, agent} -> with_pending_remote_config(server_to_agent, agent, socket)
        {:error, _} -> {server_to_agent, socket}
      end

    {:reply, {:ok, server_to_agent}, socket}
  end

  @impl true
  def handle_in("shout", payload, socket) do
    broadcast(socket, "shout", payload)
    {:noreply, socket}
  end

  @impl true
  def terminate({:shutdown, :superseded}, socket) do
    IO.puts("#{socket.assigns.agent_id} reconnected on a new connection")
    {:shutdown, socket.assigns.agent_id}
  end

  def terminate(reason, socket) do
    case reason do
      {:shutdown, :timeout} ->
        IO.puts("#{socket.assigns.agent_id} timed out")

      {:shutdown, :peer_closed} ->
        IO.puts("#{socket.assigns.agent_id} disconnected")

      other ->
        IO.inspect(other)
    end

    delete(socket.assigns.agent_id)
    {:shutdown, socket.assigns.agent_id}
  end

  # Private functions

  defp delete(agent_id) do
    case OpAMPServer.Agents.get_agent(agent_id) do
      nil ->
        {:error, "not found"}

      agent ->
        OpAMPServer.Agents.delete_agent(agent)
    end
  end

  defp create_or_update(agent_id, payload) do
    attrs = %{
      id: agent_id,
      effective_config: payload.effective_config,
      remote_config_status: payload.remote_config_status,
      component_health: payload.health,
      description: payload.agent_description,
      # 0 is the protobuf default, so the message did not set capabilities.
      capabilities: if(payload.capabilities == 0, do: nil, else: payload.capabilities)
    }

    case OpAMPServer.Agents.get_agent(agent_id) do
      nil -> OpAMPServer.Agents.create_agent(attrs)
      agent -> OpAMPServer.Agents.update_agent(agent, attrs)
    end
  end

  # The spec requires instance_uid to be the agent's 16 raw bytes, not the UUID string.
  defp response(agent_id, flags \\ 0) do
    %Opamp.Proto.ServerToAgent{
      instance_uid: Ecto.UUID.dump!(agent_id),
      capabilities: Helpers.server_capabilities(),
      flags: flags
    }
  end

  defp missing_reported_state?(agent, payload) do
    Enum.any?(@reported_state, fn {field, capability} ->
      is_nil(Map.get(agent, field)) and Helpers.agent_has_capability?(payload, capability)
    end) or
      (ConnectionSettings.offers?() and is_nil(payload.connection_settings_status) and
         Helpers.agent_has_capability?(
           payload,
           Opamp.Proto.AgentCapabilities.AgentCapabilities_ReportsConnectionSettingsStatus
         ))
  end

  # Answers a CSR with a signed certificate, or a BadRequest as the spec requires. Otherwise it
  # offers the standing connection settings once per connection, until the agent reports their hash.
  defp with_connection_settings(server_to_agent, payload, socket) do
    socket =
      case payload.connection_settings_status do
        nil -> socket
        status -> assign(socket, :connection_settings_hash, status.last_connection_settings_hash)
      end

    case payload do
      %{connection_settings_request: %{opamp: %{certificate_request: %{csr: csr}}}} ->
        answer_csr(server_to_agent, csr, socket)

      _ ->
        offer = ConnectionSettings.offer(socket.assigns.capabilities, socket.assigns.certificate)

        # While the server waits for the full state, the reported hash can be missing.
        if offer && server_to_agent.flags != @report_full_state &&
             offer.hash not in [
               socket.assigns[:connection_settings_hash],
               socket.assigns[:sent_connection_settings_hash]
             ] do
          {%{server_to_agent | connection_settings: offer},
           assign(socket, :sent_connection_settings_hash, offer.hash)}
        else
          {server_to_agent, socket}
        end
    end
  end

  defp answer_csr(server_to_agent, csr, socket) do
    agent_id = socket.assigns.agent_id

    with {:ok, certificate} <- ConnectionSettings.sign_csr(csr, agent_id),
         {:ok, _} <- OpAMPServer.Agents.put_certificate(agent_id, certificate) do
      offer = ConnectionSettings.csr_offer(socket.assigns.capabilities, certificate)

      {%{server_to_agent | connection_settings: offer},
       assign(socket, certificate: certificate, sent_connection_settings_hash: offer.hash)}
    else
      {:error, reason} ->
        Logger.warning("Rejected the CSR of agent #{agent_id}: #{inspect(reason)}")

        error = %Opamp.Proto.ServerErrorResponse{
          type: :ServerErrorResponseType_BadRequest,
          error_message:
            if(is_binary(reason), do: reason, else: "the server could not store the certificate")
        }

        {%{server_to_agent | error_response: error}, socket}
    end
  end

  # Offer the desired config once per connection, until the agent reports its hash back.
  defp with_pending_remote_config(server_to_agent, agent, socket) do
    desired = agent.desired_remote_config
    reported = agent.remote_config_status && agent.remote_config_status.last_remote_config_hash

    cond do
      is_nil(desired) or desired.config_hash in [reported, socket.assigns[:sent_config_hash]] or
          not Helpers.agent_has_capability?(
            socket.assigns,
            Opamp.Proto.AgentCapabilities.AgentCapabilities_AcceptsRemoteConfig
          ) ->
        {server_to_agent, socket}

      # The spec forbids sending a message over the limit; the 1 is the OpAMP header byte.
      byte_size(Opamp.Proto.ServerToAgent.encode(%{server_to_agent | remote_config: desired})) +
        1 > @max_message_size ->
        Logger.warning(
          "Discarded remote config for agent #{socket.assigns.agent_id}: over max_message_size"
        )

        {server_to_agent, assign(socket, :sent_config_hash, desired.config_hash)}

      true ->
        {%{server_to_agent | remote_config: desired},
         assign(socket, :sent_config_hash, desired.config_hash)}
    end
  end

  defp generate_error_response({:error, _changeset} = error) do
    # Log error but still return a response
    IO.inspect(error, label: "Agent create/update error")

    %Opamp.Proto.ServerToAgent{
      capabilities: Helpers.server_capabilities()
    }
  end
end
