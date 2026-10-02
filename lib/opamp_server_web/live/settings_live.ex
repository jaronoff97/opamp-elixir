defmodule OpAMPServerWeb.SettingsLive do
  @moduledoc """
  The server's configuration, read-only: the OpAMP endpoint and limits, the capabilities
  that the server advertises, the connection settings offers, the CA and the TLS listener.
  """
  use OpAMPServerWeb, :live_view

  import Bitwise

  alias OpAMPServer.OpAMP.ConnectionSettings
  alias OpAMPServer.OpAMP.Protocol.Helpers
  alias OpAMPServerWeb.AgentView

  @impl true
  def mount(_params, _session, socket) do
    offers = ConnectionSettings.configured_offers()
    ca = ConnectionSettings.ca_certificate()
    https = Application.get_env(:opamp_server, OpAMPServerWeb.Endpoint)[:https]

    {:ok,
     assign(socket,
       page_title: "Settings",
       offers: offers,
       ca: ca && AgentView.certificate_summary(ca),
       https: https
     )}
  end

  defp opamp_url,
    do: String.replace_prefix(OpAMPServerWeb.Endpoint.url(), "http", "ws") <> "/v1/opamp"

  defp server_capabilities do
    bits = Helpers.server_capabilities()

    for {key, bit} <- Enum.sort_by(Opamp.Proto.ServerCapabilities.mapping(), &elem(&1, 1)),
        bit != 0 and (bits &&& bit) != 0,
        do: key |> Atom.to_string() |> String.replace_prefix("ServerCapabilities_", "")
  end

  defp megabytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MiB"

  defp client_verification(https) do
    case get_in(https, [:thousand_island_options, :transport_options, :verify]) do
      :verify_peer -> "requests a certificate signed by the CA"
      _ -> "off"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={:settings}>
      <.header>
        Settings
        <:subtitle>
          This server's configuration. Set it with environment variables, see the README.
        </:subtitle>
      </.header>

      <div class="mt-6 grid gap-4 lg:grid-cols-2">
        <.card title="Server" id="server">
          <.kv_list items={[
            {"OpAMP endpoint", opamp_url()},
            {"version", to_string(Application.spec(:opamp_server, :vsn))},
            {"max message size", megabytes(Application.fetch_env!(:opamp_server, :max_message_size))}
          ]} />
          <div>
            <h3 class="mb-2 text-xs text-base-content/60">Advertised capabilities</h3>
            <div class="flex flex-wrap gap-2">
              <span :for={capability <- server_capabilities()} class="badge badge-outline badge-sm">
                {capability}
              </span>
            </div>
          </div>
        </.card>

        <.card title="TLS listener" id="tls">
          <p :if={@https == nil} class="text-sm text-base-content/60">
            Off. Set <code>OPAMP_TLS_CERT_FILE</code>
            and <code>OPAMP_TLS_KEY_FILE</code>
            to serve OpAMP over TLS.
          </p>
          <.kv_list
            :if={@https}
            items={[
              {"port", to_string(@https[:port])},
              {"client certificates", client_verification(@https)}
            ]}
          />
        </.card>

        <.card title="Connection settings offers" id="offers">
          <p :if={@offers == nil} class="text-sm text-base-content/60">
            None. Set <code>OPAMP_CONNECTION_SETTINGS_FILE</code>
            to a ConnectionSettingsOffers JSON file to offer settings to agents.
          </p>
          <div :if={@offers} class="space-y-3">
            <.kv_list items={AgentView.offer_parts(@offers)} />
            <p class="text-xs text-base-content/60">
              Each agent gets only the parts that its capabilities accept.
            </p>
          </div>
        </.card>

        <.card title="Certificate authority" id="ca">
          <p :if={@ca == nil} class="text-sm text-base-content/60">
            None. Set <code>OPAMP_CA_CERT_FILE</code>
            and <code>OPAMP_CA_KEY_FILE</code>
            to sign the CSRs that agents send.
          </p>
          <.kv_list
            :if={@ca}
            items={[
              {"subject", @ca.subject},
              {"valid until", Calendar.strftime(@ca.not_after, "%b %-d, %Y")},
              {"CSRs", "approved automatically"}
            ]}
          />
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
