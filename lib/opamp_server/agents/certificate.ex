defmodule OpAMPServer.Agents.Certificate do
  @moduledoc """
  The client certificate that the server issued to an agent through its CSR.

  The server keeps it when the agent disconnects, because every later OpAMP offer to the
  agent must repeat it (see `OpAMPServer.OpAMP.ConnectionSettings.offer/2`).
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "agent_certificate" do
    # An encoded Opamp.Proto.TLSCertificate.
    field :certificate, :binary

    timestamps(type: :utc_datetime)
  end
end
