defmodule OpAMPServer.Repo.Migrations.CreateAgent do
  use Ecto.Migration

  def change do
    create table(:agent) do
      add :instance_id, :string
      add :effective_config, :map

      timestamps(type: :utc_datetime)
    end
  end
end
