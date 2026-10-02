defmodule OpAMPServerWeb.AgentViewTest do
  use ExUnit.Case, async: true

  import OpAMPServer.AgentsFixtures, only: [collector_body: 1, collector_body: 2]

  alias OpAMPServer.Agents.Agent
  alias OpAMPServerWeb.AgentView

  defp kv(key, value),
    do: %Opamp.Proto.KeyValue{key: key, value: %Opamp.Proto.AnyValue{value: value}}

  defp agent(attrs \\ %{}) do
    struct(%Agent{id: "01a0f8a9-ca0f-7cbb-80d7-8f30d84c32a0"}, attrs)
  end

  defp described(identifying, non_identifying \\ []) do
    agent(%{
      description: %Opamp.Proto.AgentDescription{
        identifying_attributes: identifying,
        non_identifying_attributes: non_identifying
      }
    })
  end

  defp with_objects(objects, health \\ nil) do
    agent(%{
      effective_config: %Opamp.Proto.EffectiveConfig{
        config_map: %Opamp.Proto.AgentConfigMap{
          config_map:
            Map.new(objects, fn {k, body} -> {k, %Opamp.Proto.AgentConfigObject{body: body}} end)
        }
      },
      component_health: health
    })
  end

  describe "name/1 and attribute/2" do
    test "the name is service.name" do
      assert AgentView.name(described([kv("service.name", {:string_value, "bridge"})])) ==
               "bridge"
    end

    test "without service.name, the name is a short instance uid" do
      assert AgentView.name(agent()) == "agent 01a0f8a9"
    end

    test "reads identifying and non-identifying attributes of any type as strings" do
      agent =
        described([kv("service.name", {:string_value, "x"})], [
          kv("replicas", {:int_value, 3}),
          kv("debug", {:bool_value, true})
        ])

      assert AgentView.attribute(agent, "replicas") == "3"
      assert AgentView.attribute(agent, "debug") == "true"
      assert AgentView.attribute(agent, "missing") == nil

      assert AgentView.attributes(agent, :non_identifying) == [
               {"debug", "true"},
               {"replicas", "3"}
             ]
    end

    test "an agent without a description has no attributes" do
      assert AgentView.attributes(agent(), :identifying) == []
    end
  end

  describe "status/1 and last_error/1" do
    test "follows the reported health" do
      assert AgentView.status(agent()) == :unknown

      assert AgentView.status(
               agent(%{component_health: %Opamp.Proto.ComponentHealth{healthy: true}})
             ) == :healthy

      unhealthy =
        agent(%{
          component_health: %Opamp.Proto.ComponentHealth{healthy: false, last_error: "boom"}
        })

      assert AgentView.status(unhealthy) == :unhealthy
      assert AgentView.last_error(unhealthy) == "boom"
      assert AgentView.last_error(agent()) == nil
    end
  end

  test "capabilities/1 lists the set bits by name, in bit order" do
    assert AgentView.capabilities(agent()) == []

    assert AgentView.capabilities(agent(%{capabilities: 0x1 + 0x2 + 0x800})) ==
             ["ReportsStatus", "AcceptsRemoteConfig", "ReportsHealth"]
  end

  describe "config_objects/1 and kind/1" do
    test "parses each object and joins its health" do
      health = %Opamp.Proto.ComponentHealth{
        component_health_map: %{"default/a" => %Opamp.Proto.ComponentHealth{status: "1/1"}}
      }

      agent =
        with_objects(
          %{
            "default/b" => collector_body("b", %{}),
            "default/a" => collector_body("a"),
            "" => "not: [valid"
          },
          health
        )

      assert [plain, a, b] = AgentView.config_objects(agent)
      assert %{key: "", config: nil, resource?: false, managed?: false, health: nil} = plain
      assert %{key: "default/a", resource?: true, managed?: true, health: %{status: "1/1"}} = a
      assert %{key: "default/b", resource?: true, managed?: false} = b
      assert AgentView.kind(agent) == :bridge
    end

    test "an agent with plain configs, or none, is an agent" do
      assert AgentView.config_objects(agent()) == []
      assert AgentView.kind(with_objects(%{"" => "receivers: {}"})) == :agent
    end
  end

  test "pods/1 counts the ready pods of a collector" do
    pod = &%Opamp.Proto.ComponentHealth{healthy: &1}

    assert AgentView.pods(nil) == {0, 0}

    assert AgentView.pods(%Opamp.Proto.ComponentHealth{
             component_health_map: %{"p1" => pod.(true), "p2" => pod.(false)}
           }) == {1, 2}
  end

  describe "remote_config/1" do
    setup do
      %{desired: %Opamp.Proto.AgentRemoteConfig{config_hash: "h1"}}
    end

    defp status(hash, state, message \\ ""),
      do: %Opamp.Proto.RemoteConfigStatus{
        last_remote_config_hash: hash,
        status: state,
        error_message: message
      }

    test "is :none without a desired config" do
      assert AgentView.remote_config(agent()) == {:none, nil}
    end

    test "follows the status for the desired hash", %{desired: desired} do
      remote =
        &AgentView.remote_config(
          agent(%{desired_remote_config: desired, remote_config_status: &1})
        )

      assert remote.(nil) == {:pending, nil}
      assert remote.(status("old", :RemoteConfigStatuses_APPLIED)) == {:pending, nil}
      assert remote.(status("h1", :RemoteConfigStatuses_APPLIED)) == {:applied, nil}
      assert remote.(status("h1", :RemoteConfigStatuses_APPLYING)) == {:applying, nil}
      assert remote.(status("h1", :RemoteConfigStatuses_FAILED, "bad")) == {:failed, "bad"}
      assert remote.(status("h1", :RemoteConfigStatuses_UNSET)) == {:pending, nil}
    end
  end

  test "ago/2 gives a short relative time" do
    now = ~U[2026-10-01 12:00:00Z]

    assert AgentView.ago(nil, now) == "never"
    assert AgentView.ago(~U[2026-10-01 11:59:58Z], now) == "just now"
    assert AgentView.ago(~U[2026-10-01 11:59:30Z], now) == "30s ago"
    assert AgentView.ago(~U[2026-10-01 11:55:00Z], now) == "5m ago"
    assert AgentView.ago(~U[2026-10-01 09:00:00Z], now) == "3h ago"
    assert AgentView.ago(~U[2026-09-29 12:00:00Z], now) == "2d ago"
  end
end
