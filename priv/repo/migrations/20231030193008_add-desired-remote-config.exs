defmodule :"Elixir.OpAMPServer.Repo.Migrations.Add-desired-remote-config" do
  use Ecto.Migration

  def change do
    alter table(:agent) do
      add :desired_remote_config, :binary
    end
  end
end
