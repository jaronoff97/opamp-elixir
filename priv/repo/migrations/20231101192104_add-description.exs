defmodule :"Elixir.OpAMPServer.Repo.Migrations.Add-description" do
  use Ecto.Migration

  def change do
    alter table(:agent) do
      add :description, :binary
    end
  end
end
