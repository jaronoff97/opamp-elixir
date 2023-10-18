defmodule OpAMPServer.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent" do
    field :instance_id, :string
    field :effective_config, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:instance_id, :effective_config])
    |> validate_required([:instance_id])
  end
end
