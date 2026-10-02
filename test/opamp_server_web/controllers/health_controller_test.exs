defmodule OpAMPServerWeb.HealthControllerTest do
  use OpAMPServerWeb.ConnCase

  test "GET /healthz", %{conn: conn} do
    assert conn |> get(~p"/healthz") |> text_response(200) == "ok"
  end

  test "GET /readyz checks the database", %{conn: conn} do
    assert conn |> get(~p"/readyz") |> text_response(200) == "ok"
  end
end
