defmodule OpAMPServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      OpAMPServerWeb.Telemetry,
      OpAMPServer.Repo,
      {DNSCluster, query: Application.get_env(:opamp_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: OpAMPServer.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: OpAMPServer.Finch},
      # Start a worker by calling: OpAMPServer.Worker.start_link(arg)
      # {OpAMPServer.Worker, arg},
      # Start to serve requests, typically the last entry
      OpAMPServerWeb.Endpoint,
      OpAMPServerWeb.Serializer
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: OpAMPServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OpAMPServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
