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
end
