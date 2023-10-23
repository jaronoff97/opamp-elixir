defmodule OpAMPServer.Repo.Migrations.CreateAgent do
  use Ecto.Migration

  def change do
    create table(:agent, primary_key: false) do
      add :id, :string, primary_key: true
      add :effective_config, :map

      timestamps(type: :utc_datetime)
    end
  end
end
