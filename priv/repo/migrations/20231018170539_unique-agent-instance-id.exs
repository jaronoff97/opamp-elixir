defmodule :"Elixir.OpAMPServer.Repo.Migrations.Unique-agent-instance-id" do
  use Ecto.Migration

  def change do
    create unique_index(:agent, [:id])
  end
end
