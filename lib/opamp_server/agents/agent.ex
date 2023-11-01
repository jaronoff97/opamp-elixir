defmodule OpAMPServer.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "agent" do
    # field :instance_id, :string, primary_key: true
    field :effective_config, Opamp.Proto.EffectiveConfig
    field :desired_remote_config, Opamp.Proto.AgentRemoteConfig
    field :remote_config_status, Opamp.Proto.RemoteConfigStatus
    field :component_health, Opamp.Proto.ComponentHealth
    field :description, Opamp.Proto.AgentDescription

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:id, :effective_config, :remote_config_status, :component_health, :desired_remote_config, :description])
    |> remove_nil([:effective_config, :remote_config_status, :component_health, :desired_remote_config, :description])
    |> unique_constraint(:id)
    |> validate_required([:id])
  end

  def remove_nil(changeset, fields) do 
    Enum.reduce(fields, changeset, fn field, changeset -> 
      case fetch_change(changeset, field) do
        {:ok, nil} -> delete_change(changeset, field)
        _ -> changeset
      end
    end)
  end
end
