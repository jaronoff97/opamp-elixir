defmodule OpAMPServer.OpAMP.ConnectionSettings do
  @moduledoc """
  Connection settings that the server offers to agents (spec: Connection Settings Management).

  Both parts are optional and come from `config :opamp_server, :connection_settings`:

    * `:offers_file` - a `ConnectionSettingsOffers` in the proto3 JSON mapping. The server
      offers each part only to agents with the matching capability.
    * `:ca_cert_file` and `:ca_key_file` - a local CA. With it, the server signs and
      auto-approves the CSRs that agents send (Agent-initiated CSR Flow).
    * `:cert_validity_days` - the validity of the certificates the CA issues (default 365).
  """

  alias Opamp.Proto.AgentCapabilities
  alias Opamp.Proto.{ConnectionSettingsOffers, OpAMPConnectionSettings, TLSCertificate}
  alias OpAMPServer.OpAMP.Protocol.Helpers

  # Each part of an offer, and the agent capability that allows the server to offer it.
  @parts [
    own_metrics: AgentCapabilities.AgentCapabilities_ReportsOwnMetrics,
    own_traces: AgentCapabilities.AgentCapabilities_ReportsOwnTraces,
    own_logs: AgentCapabilities.AgentCapabilities_ReportsOwnLogs,
    other_connections: AgentCapabilities.AgentCapabilities_AcceptsOtherConnectionSettings
  ]

  @uuid ~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i

  @doc """
  Reads the configured files. The application calls this once at boot, so bad config stops the start.
  """
  def load! do
    config = Application.get_env(:opamp_server, :connection_settings, [])

    put(%{
      offers:
        config[:offers_file] &&
          Protobuf.JSON.decode!(File.read!(config[:offers_file]), ConnectionSettingsOffers),
      ca:
        config[:ca_cert_file] &&
          {X509.Certificate.from_pem!(File.read!(config[:ca_cert_file])),
           X509.PrivateKey.from_pem!(File.read!(Keyword.fetch!(config, :ca_key_file)))},
      cert_validity_days: config[:cert_validity_days] || 365
    })
  end

  @doc false
  def put(settings), do: Application.put_env(:opamp_server, __MODULE__, settings)

  defp loaded,
    do:
      Application.get_env(:opamp_server, __MODULE__, %{
        offers: nil,
        ca: nil,
        cert_validity_days: 365
      })

  @doc "True if the server has connection settings to offer. A CSR response is also an offer."
  def offers?, do: loaded().offers != nil or signs_csrs?()

  @doc "True if the server has a CA to sign agent CSRs."
  def signs_csrs?, do: loaded().ca != nil

  @doc "The configured offers, before the server filters them for each agent, or nil."
  def configured_offers, do: loaded().offers

  @doc "The CA certificate (an X509 OTP certificate), or nil."
  def ca_certificate do
    case loaded().ca do
      {certificate, _key} -> certificate
      nil -> nil
    end
  end

  @doc """
  Returns the offer for an agent with these capabilities, or nil if there is nothing to offer.

  `certificate` is the client certificate that the server issued to the agent, or nil. Every
  OpAMP offer must repeat it: an `opamp` offer without a certificate tells the agent to stop
  using its client certificate.
  """
  def offer(capabilities, certificate) do
    # ponytail: an agent applies an opamp offer by reconnecting, so without status reports the
    # server cannot tell that it already applied it and would offer it again on every connection.
    build(
      capabilities,
      certificate,
      has?(capabilities, AgentCapabilities.AgentCapabilities_ReportsConnectionSettingsStatus)
    )
  end

  @doc "Returns the offer that answers a CSR: the standing offer, with the new certificate."
  def csr_offer(capabilities, %TLSCertificate{} = certificate),
    do: build(capabilities, certificate, true)

  defp build(capabilities, certificate, include_opamp?) do
    offers = loaded().offers || %ConnectionSettingsOffers{}

    opamp =
      if include_opamp? and
           has?(capabilities, AgentCapabilities.AgentCapabilities_AcceptsOpAMPConnectionSettings),
         do: opamp_settings(offers.opamp, certificate)

    offer =
      Enum.reduce(@parts, %ConnectionSettingsOffers{opamp: opamp}, fn {part, capability}, acc ->
        if has?(capabilities, capability),
          do: Map.put(acc, part, Map.get(offers, part)),
          else: acc
      end)

    if offer == %ConnectionSettingsOffers{},
      do: nil,
      else: %{offer | hash: :crypto.hash(:sha256, ConnectionSettingsOffers.encode(offer))}
  end

  defp opamp_settings(nil, nil), do: nil
  defp opamp_settings(%OpAMPConnectionSettings{} = settings, nil), do: settings

  defp opamp_settings(nil, certificate),
    do: %OpAMPConnectionSettings{
      destination_endpoint: default_endpoint(),
      certificate: certificate
    }

  defp opamp_settings(settings, certificate), do: %{settings | certificate: certificate}

  # The spec requires a destination_endpoint, so default to this server's public URL.
  defp default_endpoint do
    String.replace_prefix(OpAMPServerWeb.Endpoint.url(), "http", "ws") <> "/v1/opamp"
  end

  defp has?(capabilities, capability),
    do: Helpers.agent_has_capability?(%{capabilities: capabilities}, capability)

  @doc """
  Signs an agent's PEM-encoded CSR with the local CA. The server approves every valid CSR.

  Returns `{:ok, %TLSCertificate{}}` or `{:error, message}`. The private key stays with the agent.
  """
  def sign_csr(csr_pem, agent_id) do
    %{ca: ca, cert_validity_days: days} = loaded()

    with {:ca, {ca_cert, ca_key}} <- {:ca, ca},
         {:ok, csr} <- X509.CSR.from_pem(csr_pem),
         {:valid, true} <- {:valid, X509.CSR.valid?(csr)},
         san =
           X509.Certificate.Extension.find(requested_extensions(csr), :subject_alt_name),
         :ok <- check_instance_uid(csr, san, agent_id) do
      cert =
        X509.Certificate.new(X509.CSR.public_key(csr), X509.CSR.subject(csr), ca_cert, ca_key,
          validity: days,
          extensions: [
            ext_key_usage: X509.Certificate.Extension.ext_key_usage([:clientAuth]),
            subject_alt_name: san || false
          ]
        )

      {:ok,
       %TLSCertificate{
         cert: X509.Certificate.to_pem(cert),
         ca_cert: X509.Certificate.to_pem(ca_cert)
       }}
    else
      {:ca, nil} ->
        {:error, "the server has no CA to sign certificate requests"}

      {:valid, false} ->
        {:error, "the CSR signature is not valid"}

      {:error, reason} when reason in [:malformed, :not_found] ->
        {:error, "the CSR is not a valid PEM certificate request"}

      {:error, message} when is_binary(message) ->
        {:error, message}
    end
  end

  # X509.CSR.extension_request/1 returns [] for a CSR read from PEM: it matches another record
  # tag than the one :public_key decodes the attribute to. So decode the extensionRequest here.
  defp requested_extensions({:CertificationRequest, info, _algorithm, _signature}) do
    for {_tag, {1, 2, 840, 113_549, 1, 9, 14}, [asn1_OPENTYPE: der]} <- elem(info, 4),
        extension <- X509.Certificate.Extension.from_der!(der, :Extensions),
        do: extension
  end

  # Spec: if the CSR names an instance_uid, it MUST be the instance_uid of the agent that sent it.
  defp check_instance_uid(csr, san, agent_id) do
    sans = for {_type, value} <- (san && elem(san, 3)) || [], is_list(value), do: to_string(value)

    [X509.RDNSequence.to_string(X509.CSR.subject(csr)) | sans]
    |> Enum.flat_map(&Regex.scan(@uuid, &1))
    |> List.flatten()
    |> Enum.all?(&(String.downcase(&1) == agent_id))
    |> if(do: :ok, else: {:error, "the CSR names an instance_uid other than the agent's"})
  end
end
