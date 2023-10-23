defmodule :"Elixir.OpAMPServer.Repo.Migrations.Store-as-binary" do
  use Ecto.Migration

  def up do
    alter table(:agent) do
      remove :effective_config
      add :effective_config, :binary
    end
  end

  def down do
    alter table(:agent) do
      remove :effective_config
      add :effective_config, :map
    end
  end
end
