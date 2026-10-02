defmodule OpAMPServer.CollectorConfigTest do
  use ExUnit.Case, async: true

  alias OpAMPServer.CollectorConfig

  @config """
  receivers:
    otlp: {}
    prometheus: {}
  processors:
    batch: {}
    memory_limiter: {}
  exporters:
    debug: {}
  connectors:
    spanmetrics: {}
  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [debug, spanmetrics]
      metrics/spans:
        receivers: [spanmetrics]
        exporters: [debug]
  """

  defp resource(labels) do
    """
    apiVersion: opentelemetry.io/v1beta1
    kind: OpenTelemetryCollector
    metadata:
      name: simplest
      namespace: default
      labels: #{Jason.encode!(labels)}
    spec:
      config:
        receivers: {otlp: {}}
    """
  end

  test "reads a plain collector config" do
    {:ok, config} = CollectorConfig.parse(@config)

    refute CollectorConfig.resource?(config)
    assert CollectorConfig.managed?(config)
    assert CollectorConfig.components(config, "receivers") == ["otlp", "prometheus"]
    assert CollectorConfig.components(config, "connectors") == ["spanmetrics"]
    assert CollectorConfig.components(config, "extensions") == []
  end

  test "reads the pipelines, sorted by name" do
    {:ok, config} = CollectorConfig.parse(@config)

    assert [
             %{
               name: "metrics/spans",
               receivers: ["spanmetrics"],
               processors: [],
               exporters: ["debug"]
             },
             %{
               name: "traces",
               receivers: ["otlp"],
               processors: ["memory_limiter", "batch"],
               exporters: ["debug", "spanmetrics"]
             }
           ] = CollectorConfig.pipelines(config)
  end

  test "reads the config inside an OpenTelemetryCollector resource" do
    {:ok, config} = CollectorConfig.parse(resource(%{"opentelemetry.io/opamp-managed" => "true"}))

    assert CollectorConfig.resource?(config)
    assert CollectorConfig.name(config) == "simplest"
    assert CollectorConfig.namespace(config) == "default"
    assert CollectorConfig.components(config, "receivers") == ["otlp"]
    assert CollectorConfig.pipelines(config) == []
  end

  test "a resource is managed only with the opamp-managed label and without opamp-reporting" do
    managed? = fn labels ->
      {:ok, config} = CollectorConfig.parse(resource(labels))
      CollectorConfig.managed?(config)
    end

    assert managed?.(%{"opentelemetry.io/opamp-managed" => "true"})
    assert managed?.(%{"opentelemetry.io/opamp-managed" => "TRUE"})
    assert managed?.(%{"opentelemetry.io/opamp-managed" => "my-bridge"})
    refute managed?.(%{})
    refute managed?.(%{"opentelemetry.io/opamp-managed" => "false"})

    refute managed?.(%{
             "opentelemetry.io/opamp-managed" => "true",
             "opentelemetry.io/opamp-reporting" => "true"
           })
  end

  test "rejects a body that is not a YAML map" do
    assert CollectorConfig.parse(": not yaml : [") == :error
    assert CollectorConfig.parse("just a string") == :error
    assert CollectorConfig.parse(nil) == :error
  end

  test "ignores malformed sections" do
    {:ok, config} = CollectorConfig.parse("receivers: [otlp]\nservice:\n  pipelines: nope\n")

    assert CollectorConfig.components(config, "receivers") == []
    assert CollectorConfig.pipelines(config) == []
  end

  test "the signal of a pipeline is the name before the slash" do
    assert CollectorConfig.signal("traces") == "traces"
    assert CollectorConfig.signal("metrics/spans") == "metrics"
  end
end
