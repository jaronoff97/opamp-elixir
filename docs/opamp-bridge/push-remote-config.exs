# Sets the desired remote config of every connected agent. The channel then sends it to the bridge.
# Run it on the server node: elixir --sname driver --rpc-eval "opamp@$(hostname -s)" "$(cat <this file>)"
collector = fn processors ->
  """
  apiVersion: opentelemetry.io/v1beta1
  kind: OpenTelemetryCollector
  metadata:
    labels:
      opentelemetry.io/opamp-managed: "true"
  spec:
    config:
      receivers:
        otlp:
          protocols:
            grpc: {}
            http: {}
      processors:
        memory_limiter:
          check_interval: 1s
          limit_percentage: 75
          spike_limit_percentage: 15
        batch: {}
      exporters:
        debug: {}
      service:
        pipelines:
          traces:
            receivers: [otlp]
            processors: #{inspect(processors)}
            exporters: [debug]
  """
end

# The bridge deletes every managed collector that the remote config omits, so list all of them.
config = %Opamp.Proto.AgentConfigMap{
  config_map: %{
    "default/simplest" => %Opamp.Proto.AgentConfigObject{
      body: collector.(["memory_limiter", "batch"]),
      content_type: "yaml"
    },
    "default/from-server" => %Opamp.Proto.AgentConfigObject{
      body: collector.(["batch"]),
      content_type: "yaml"
    }
  }
}

for agent <- OpAMPServer.Agents.list_agent() do
  remote_config = OpAMPServer.Agents.generate_desired_remote_config(config)
  {:ok, _} = OpAMPServer.Agents.update_agent(agent, %{desired_remote_config: remote_config})
  IO.puts("sent config #{Base.encode16(remote_config.config_hash)} to #{agent.id}")
end
