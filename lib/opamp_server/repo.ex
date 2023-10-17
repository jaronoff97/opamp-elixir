defmodule OpAMPServer.Repo do
  use Ecto.Repo,
    otp_app: :opamp_server,
    adapter: Ecto.Adapters.Postgres
end
