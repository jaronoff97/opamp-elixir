defmodule OpAMPServer.Repo.Migrations.AddTelemetrySettings do
  use Ecto.Migration

  def change do
    alter table(:agent) do
      add :connection_settings, :binary
    end
  end
end
