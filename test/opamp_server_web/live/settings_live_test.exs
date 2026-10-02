defmodule OpAMPServerWeb.SettingsLiveTest do
  use OpAMPServerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias OpAMPServer.OpAMP.ConnectionSettings

  setup do
    on_exit(fn -> Application.delete_env(:opamp_server, ConnectionSettings) end)
  end

  test "shows the endpoint, the limits and the advertised capabilities", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    server = view |> element("#server") |> render()
    assert server =~ "/v1/opamp"
    assert server =~ "MiB"

    for capability <- ~w(AcceptsStatus OffersRemoteConfig AcceptsEffectiveConfig) do
      assert server =~ capability
    end

    refute server =~ "OffersConnectionSettings"
    assert has_element?(view, "nav a[aria-current=page]", "Settings")
  end

  test "explains how to turn on each optional feature", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert view |> element("#tls") |> render() =~ "OPAMP_TLS_CERT_FILE"
    assert view |> element("#offers") |> render() =~ "OPAMP_CONNECTION_SETTINGS_FILE"
    assert view |> element("#ca") |> render() =~ "OPAMP_CA_CERT_FILE"
  end

  test "shows the configured offers and CA", %{conn: conn} do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "/CN=Settings CA", template: :root_ca)

    ConnectionSettings.put(%{
      offers: %Opamp.Proto.ConnectionSettingsOffers{
        own_logs: %Opamp.Proto.TelemetryConnectionSettings{
          destination_endpoint: "https://logs:4318"
        }
      },
      ca: {ca, ca_key},
      cert_validity_days: 30
    })

    {:ok, view, _html} = live(conn, ~p"/settings")

    assert view |> element("#offers") |> render() =~ "https://logs:4318"
    assert view |> element("#ca") |> render() =~ "/CN=Settings CA"

    server = view |> element("#server") |> render()
    assert server =~ "OffersConnectionSettings"
    assert server =~ "AcceptsConnectionSettingsRequest"
  end
end
