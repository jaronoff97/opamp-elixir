defmodule OpAMPServer.Agents do
  @moduledoc """
  The Agents context.
  """

  import Ecto.Query, warn: false
  alias OpAMPServer.Repo

  alias OpAMPServer.Agents.Agent

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

  def generate_desired_remote_config(conf) do
    %Opamp.Proto.AgentRemoteConfig{
      config_hash: :crypto.hash(:md5, Opamp.Proto.AgentConfigMap.encode(conf)),
      config: conf
    }
  end
end
