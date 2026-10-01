defmodule OpAMPServer.OpAMP.ConnectionSettingsTest do
  # ConnectionSettings keeps its state in the application env.
  use ExUnit.Case, async: false
  use OpAMPServer.OpAMPCase

  import Bitwise

  alias OpAMPServer.OpAMP.ConnectionSettings
  alias Opamp.Proto.{ConnectionSettingsOffers, TelemetryConnectionSettings, TLSCertificate}

  @own_metrics 0x40
  @accepts_opamp 0x100
  @reports_status 0x8000

  setup do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "/CN=Test CA", template: :root_ca)

    ConnectionSettings.put(%{
      offers: %ConnectionSettingsOffers{
        own_metrics: %TelemetryConnectionSettings{destination_endpoint: "https://otlp:4318"},
        own_logs: %TelemetryConnectionSettings{destination_endpoint: "https://otlp:4318"}
      },
      ca: {ca, ca_key},
      cert_validity_days: 30
    })

    on_exit(fn -> Application.delete_env(:opamp_server, ConnectionSettings) end)
    %{ca: ca, agent_id: generate_instance_uid_string()}
  end

  describe "offer/2" do
    test "offers each part only to agents with the matching capability" do
      offer = ConnectionSettings.offer(@own_metrics, nil)

      assert offer.own_metrics.destination_endpoint == "https://otlp:4318"
      assert offer.own_logs == nil
      assert byte_size(offer.hash) == 32
      assert ConnectionSettings.offer(0, nil) == nil
    end

    test "offers opamp settings only to agents that report connection settings status" do
      certificate = %TLSCertificate{cert: "cert"}

      assert ConnectionSettings.offer(@accepts_opamp, certificate) == nil

      offer = ConnectionSettings.offer(@accepts_opamp ||| @reports_status, certificate)
      assert offer.opamp.certificate == certificate
      assert offer.opamp.destination_endpoint =~ ~r"^ws.*/v1/opamp$"
    end

    test "a CSR offer matches the standing offer, so the agent is not offered it again" do
      capabilities = @accepts_opamp ||| @reports_status ||| @own_metrics
      certificate = %TLSCertificate{cert: "cert"}

      assert ConnectionSettings.csr_offer(capabilities, certificate) ==
               ConnectionSettings.offer(capabilities, certificate)

      assert ConnectionSettings.csr_offer(@accepts_opamp, certificate).opamp.certificate ==
               certificate
    end
  end

  describe "sign_csr/2" do
    test "issues a client certificate signed by the CA", %{ca: ca, agent_id: agent_id} do
      csr = X509.CSR.new(X509.PrivateKey.new_ec(:secp256r1), "/CN=#{agent_id}")

      assert {:ok, %TLSCertificate{cert: pem, ca_cert: ca_pem, private_key: ""}} =
               ConnectionSettings.sign_csr(X509.CSR.to_pem(csr), agent_id)

      cert = X509.Certificate.from_pem!(pem)
      assert ca_pem == X509.Certificate.to_pem(ca)
      assert X509.RDNSequence.to_string(X509.Certificate.subject(cert)) == "/CN=#{agent_id}"

      assert :public_key.pkix_verify(
               X509.Certificate.to_der(cert),
               X509.Certificate.public_key(ca)
             )

      eku = X509.Certificate.extension(cert, :ext_key_usage)
      assert elem(eku, 3) == [{1, 3, 6, 1, 5, 5, 7, 3, 2}]
    end

    test "rejects a CSR that names another instance_uid", %{agent_id: agent_id} do
      key = X509.PrivateKey.new_ec(:secp256r1)
      other = generate_instance_uid_string()

      for csr <- [
            X509.CSR.new(key, "/CN=#{other}"),
            X509.CSR.new(key, "/CN=agent",
              extension_request: [
                X509.Certificate.Extension.subject_alt_name(
                  uniformResourceIdentifier: ~c"urn:uuid:#{other}"
                )
              ]
            )
          ] do
        assert {:error, "the CSR names an instance_uid other than the agent's"} =
                 ConnectionSettings.sign_csr(X509.CSR.to_pem(csr), agent_id)
      end
    end

    test "rejects a malformed CSR", %{agent_id: agent_id} do
      assert {:error, _} = ConnectionSettings.sign_csr("not a csr", agent_id)
    end

    test "rejects every CSR without a CA", %{agent_id: agent_id} do
      ConnectionSettings.put(%{offers: nil, ca: nil, cert_validity_days: 365})
      csr = X509.CSR.new(X509.PrivateKey.new_ec(:secp256r1), "/CN=#{agent_id}")

      assert {:error, "the server has no CA to sign certificate requests"} =
               ConnectionSettings.sign_csr(X509.CSR.to_pem(csr), agent_id)

      refute ConnectionSettings.offers?()
    end
  end
end
