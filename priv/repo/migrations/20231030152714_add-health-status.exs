defmodule :"Elixir.OpAMPServer.Repo.Migrations.Add-health-status" do
  use Ecto.Migration

  def change do
    alter table(:agent) do
      add :component_health, :binary
    end
  end
end
