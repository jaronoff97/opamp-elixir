defmodule OpAMPServer.AgentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `OpAMPServer.Agents` context.
  """

  @doc """
  Generate a agent.
  """
  def agent_fixture(attrs \\ %{}) do
    {:ok, agent} =
      attrs
      |> Enum.into(%{
        id: Ecto.UUID.generate(),
        description: %Opamp.Proto.AgentDescription{
          identifying_attributes: [
            %Opamp.Proto.KeyValue{
              key: "service.name",
              value: %Opamp.Proto.AnyValue{value: {:string_value, "test-service"}}
            },
            %Opamp.Proto.KeyValue{
              key: "host.name",
              value: %Opamp.Proto.AnyValue{value: {:string_value, "test-host"}}
            }
          ],
          non_identifying_attributes: [
            %Opamp.Proto.KeyValue{
              key: "os.family",
              value: %Opamp.Proto.AnyValue{value: {:string_value, "linux"}}
            }
          ]
        },
        effective_config: %Opamp.Proto.EffectiveConfig{
          config_map: %Opamp.Proto.AgentConfigMap{
            config_map: %{}
          }
        },
        remote_config_status: %Opamp.Proto.RemoteConfigStatus{
          last_remote_config_hash: <<>>,
          status: :RemoteConfigStatuses_UNSET,
          error_message: ""
        },
        component_health: %Opamp.Proto.ComponentHealth{
          healthy: true,
          start_time_unix_nano: System.os_time(:nanosecond),
          status_time_unix_nano: System.os_time(:nanosecond),
          status: "OK",
          component_health_map: %{}
        }
      })
      |> OpAMPServer.Agents.create_agent()

    agent
  end

  @doc """
  The body of an OpenTelemetryCollector resource, as the OpAMP Bridge reports it.
  """
  def collector_body(name, labels \\ %{"opentelemetry.io/opamp-managed" => "true"}) do
    """
    apiVersion: opentelemetry.io/v1beta1
    kind: OpenTelemetryCollector
    metadata:
      name: #{name}
      labels: #{Jason.encode!(labels)}
    spec: {}
    """
  end

  @doc """
  An effective config with one object for each `key => body`.
  """
  def effective_config_fixture(objects) do
    %Opamp.Proto.EffectiveConfig{
      config_map: %Opamp.Proto.AgentConfigMap{
        config_map:
          Map.new(objects, fn {key, body} ->
            {key, %Opamp.Proto.AgentConfigObject{body: body, content_type: "yaml"}}
          end)
      }
    }
  end

  @doc """
  Component health for `collector => [pod name]`, as the OpAMP Bridge reports it.
  All times are `time` (a DateTime).
  """
  def health_fixture(collectors, time \\ ~U[2026-01-02 03:04:05Z]) do
    nanos = DateTime.to_unix(time, :nanosecond)

    health = fn status, children ->
      %Opamp.Proto.ComponentHealth{
        healthy: true,
        status: status,
        start_time_unix_nano: nanos,
        status_time_unix_nano: nanos,
        component_health_map: children
      }
    end

    health.(
      "OK",
      Map.new(collectors, fn {collector, pods} ->
        {collector,
         health.("#{length(pods)}/#{length(pods)}", Map.new(pods, &{&1, health.("Running", %{})}))}
      end)
    )
  end
end
