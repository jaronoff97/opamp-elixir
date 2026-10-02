defmodule OpAMPServer.Repo.Migrations.AddAgentCapabilities do
  use Ecto.Migration

  def change do
    alter table(:agent) do
      add :capabilities, :bigint
    end
  end
end
