defmodule :"Elixir.OpAMPServer.Repo.Migrations.Add-remote-config-status" do
  use Ecto.Migration

  def change do
    alter table(:agent) do
      add :remote_config_status, :binary
    end
  end
end
