defmodule OpAMPServerWeb.HealthController do
  @moduledoc """
  Liveness and readiness probes. Liveness only says that the node serves HTTP. Readiness
  also checks the database, because the server cannot store agents without it.
  """
  use OpAMPServerWeb, :controller

  def live(conn, _params), do: text(conn, "ok")

  def ready(conn, _params) do
    case Ecto.Adapters.SQL.query(OpAMPServer.Repo, "SELECT 1", []) do
      {:ok, _} -> text(conn, "ok")
      {:error, _} -> conn |> put_status(:service_unavailable) |> text("database unavailable")
    end
  end
end
