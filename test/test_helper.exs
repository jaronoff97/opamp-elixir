ExUnit.start()

# Only configure the Ecto sandbox if the Repo is available
if Code.ensure_loaded?(OpAMPServer.Repo) do
  try do
    Ecto.Adapters.SQL.Sandbox.mode(OpAMPServer.Repo, :manual)
  rescue
    _ -> :ok
  end
end
