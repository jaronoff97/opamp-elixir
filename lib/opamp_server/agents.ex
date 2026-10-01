defmodule OpAMPServer.Agents do
  @moduledoc """
  The Agents context.
  """

  import Ecto.Query, warn: false
  alias OpAMPServer.Repo

  alias OpAMPServer.Agents.{Agent, Certificate}

  def subscribe do
    Phoenix.PubSub.subscribe(OpAMPServer.PubSub, "agents")
  end

  def subscribe_to_agent(agent_id) do
    Phoenix.PubSub.subscribe(OpAMPServer.PubSub, "agents:" <> agent_id)
  end

  defp broadcast({:error, _reason} = error, _event), do: error

  defp broadcast({:ok, agent}, event) do
    Phoenix.PubSub.broadcast(OpAMPServer.PubSub, "agents", {event, agent})
    Phoenix.PubSub.broadcast(OpAMPServer.PubSub, "agents:" <> agent.id, {event, agent})
    {:ok, agent}
  end

  @doc """
  Returns the list of agent.

  ## Examples

      iex> list_agent()
      [%Agent{}, ...]

  """
  def list_agent do
    Repo.all(Agent)
  end

  @doc """
  Gets a single agent.

  Raises `Ecto.NoResultsError` if the Agent does not exist.

  ## Examples

      iex> get_agent!(123)
      %Agent{}

      iex> get_agent!(456)
      ** (Ecto.NoResultsError)

  """
  def get_agent!(id), do: Repo.get!(Agent, id)

  def get_agent(id), do: Repo.get(Agent, id)

  @doc """
  Creates a agent.

  ## Examples

      iex> create_agent(%{field: value})
      {:ok, %Agent{}}

      iex> create_agent(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_agent(attrs \\ %{}) do
    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:agent_created)
  end

  @doc """
  Updates a agent.

  ## Examples

      iex> update_agent(agent, %{field: new_value})
      {:ok, %Agent{}}

      iex> update_agent(agent, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_agent(%Agent{} = agent, attrs) do
    resp =
      agent
      |> Agent.changeset(attrs)
      |> Repo.update()
      |> broadcast(:agent_updated)

    resp
  end

  @doc """
  Deletes a agent.

  ## Examples

      iex> delete_agent(agent)
      {:ok, %Agent{}}

      iex> delete_agent(agent)
      {:error, %Ecto.Changeset{}}

  """
  def delete_agent(%Agent{} = agent) do
    Repo.delete(agent)
    |> broadcast(:agent_deleted)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking agent changes.

  ## Examples

      iex> change_agent(agent)
      %Ecto.Changeset{data: %Agent{}}

  """
  def change_agent(%Agent{} = agent, attrs \\ %{}) do
    Agent.changeset(agent, attrs)
  end

  @doc """
  Returns the client certificate (an `Opamp.Proto.TLSCertificate`) issued to the agent, or nil.
  """
  def get_certificate(agent_id) do
    case Repo.get(Certificate, agent_id) do
      nil -> nil
      row -> Opamp.Proto.TLSCertificate.decode(row.certificate)
    end
  end

  @doc """
  Stores the client certificate issued to the agent, and replaces any earlier one.
  """
  def put_certificate(agent_id, %Opamp.Proto.TLSCertificate{} = certificate) do
    Repo.insert(
      %Certificate{id: agent_id, certificate: Opamp.Proto.TLSCertificate.encode(certificate)},
      on_conflict: {:replace, [:certificate, :updated_at]},
      conflict_target: :id
    )
  end

  @doc """
  Returns the agent's complete config map, with the body of the object at `key` replaced.

  A remote config replaces the whole config of the agent. For example, the OpAMP Bridge deletes
  every managed collector that a remote config omits. So the map starts from all objects that the
  agent reports in its effective config, plus the server's desired config, which wins on a conflict.
  The edited object keeps its content_type and role.
  """
  def config_map_with(%Agent{} = agent, key, body) do
    effective =
      for {k, object} <- agent.effective_config.config_map.config_map,
          not unmanaged_collector?(object.body),
          into: %{},
          do: {k, object}

    desired =
      case agent.desired_remote_config do
        %{config: %{config_map: config_map}} -> config_map
        _ -> %{}
      end

    objects = Map.merge(effective, desired)
    object = Map.get(objects, key) || %Opamp.Proto.AgentConfigObject{}

    %Opamp.Proto.AgentConfigMap{config_map: Map.put(objects, key, %{object | body: body})}
  end

  # The OpAMP Bridge also reports collectors that it must not change, and it rejects a remote
  # config for them. It manages a collector only with the opamp-managed label and without
  # `opamp-reporting: "true"`. Bodies of other agents are not collector resources, so they stay.
  defp unmanaged_collector?(body) do
    case YamlElixir.read_from_string(body) do
      {:ok, %{"kind" => "OpenTelemetryCollector"} = collector} ->
        labels = get_in(collector, ["metadata", "labels"]) || %{}
        label = &String.downcase(to_string(labels[&1]))

        label.("opentelemetry.io/opamp-managed") in ["", "false"] or
          label.("opentelemetry.io/opamp-reporting") == "true"

      _ ->
        false
    end
  end

  def generate_desired_remote_config(conf) do
    %Opamp.Proto.AgentRemoteConfig{
      config_hash: :crypto.hash(:md5, Opamp.Proto.AgentConfigMap.encode(conf)),
      config: conf
    }
  end
end
