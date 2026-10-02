defmodule OpAMPServer.Repo.Migrations.CreateAgentCertificate do
  use Ecto.Migration

  def change do
    create table(:agent_certificate, primary_key: false) do
      add :id, :string, primary_key: true
      add :certificate, :binary, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
