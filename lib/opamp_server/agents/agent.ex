defmodule OpAMPServer.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "agent" do
    # field :instance_id, :string, primary_key: true
    field :effective_config, Opamp.Proto.EffectiveConfig

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:id, :effective_config])
    |> unique_constraint(:id)
    |> validate_required([:id])
  end
end
