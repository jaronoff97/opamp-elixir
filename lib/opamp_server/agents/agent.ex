defmodule OpAMPServer.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  alias OpAMPServer.OpAMP.EctoTypes

  @primary_key {:id, :string, autogenerate: false}
  schema "agent" do
    field :effective_config, EctoTypes.EffectiveConfig
    field :desired_remote_config, EctoTypes.AgentRemoteConfig
    field :remote_config_status, EctoTypes.RemoteConfigStatus
    field :component_health, EctoTypes.ComponentHealth
    field :description, EctoTypes.AgentDescription

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :id,
      :effective_config,
      :remote_config_status,
      :component_health,
      :desired_remote_config,
      :description
    ])
    |> remove_nil([
      :effective_config,
      :remote_config_status,
      :component_health,
      :desired_remote_config,
      :description
    ])
    |> unique_constraint(:id)
    |> validate_required([:id])
  end

  defp remove_nil(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      case fetch_change(changeset, field) do
        {:ok, nil} -> delete_change(changeset, field)
        _ -> changeset
      end
    end)
  end
end
