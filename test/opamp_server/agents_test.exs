defmodule OpAMPServer.AgentsTest do
  use OpAMPServer.DataCase

  alias OpAMPServer.Agents

  describe "agent" do
    alias OpAMPServer.Agents.Agent

    import OpAMPServer.AgentsFixtures

    @invalid_attrs %{id: nil}

    test "list_agent/0 returns all agent" do
      agent = agent_fixture()
      assert Agents.list_agent() == [agent]
    end

    test "get_agent!/1 returns the agent with given id" do
      agent = agent_fixture()
      assert Agents.get_agent!(agent.id) == agent
    end

    test "create_agent/1 with valid data creates a agent" do
      valid_attrs = %{id: Ecto.UUID.generate()}

      assert {:ok, %Agent{} = agent} = Agents.create_agent(valid_attrs)
      assert agent.id == valid_attrs.id
    end

    test "create_agent/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Agents.create_agent(@invalid_attrs)
    end

    test "update_agent/2 with valid data updates the agent" do
      agent = agent_fixture()

      config = %Opamp.Proto.EffectiveConfig{
        config_map: %Opamp.Proto.AgentConfigMap{config_map: %{}}
      }

      update_attrs = %{effective_config: config}

      assert {:ok, %Agent{} = updated_agent} = Agents.update_agent(agent, update_attrs)
      assert updated_agent.effective_config != nil
    end

    test "update_agent/2 with invalid data returns error changeset" do
      agent = agent_fixture()
      # Setting id to nil should fail since it's required
      assert {:error, %Ecto.Changeset{}} = Agents.update_agent(agent, %{id: nil})
    end

    test "delete_agent/1 deletes the agent" do
      agent = agent_fixture()
      assert {:ok, %Agent{}} = Agents.delete_agent(agent)
      assert_raise Ecto.NoResultsError, fn -> Agents.get_agent!(agent.id) end
    end

    test "change_agent/1 returns a agent changeset" do
      agent = agent_fixture()
      assert %Ecto.Changeset{} = Agents.change_agent(agent)
    end
  end

  describe "config_map_with/3" do
    import OpAMPServer.AgentsFixtures

    defp collector(labels) do
      """
      apiVersion: opentelemetry.io/v1beta1
      kind: OpenTelemetryCollector
      metadata:
        labels: #{Jason.encode!(labels)}
      spec: {}
      """
    end

    defp agent_with(objects, desired \\ nil) do
      agent_fixture(%{
        effective_config: %Opamp.Proto.EffectiveConfig{
          config_map: %Opamp.Proto.AgentConfigMap{config_map: objects}
        },
        desired_remote_config:
          desired &&
            Agents.generate_desired_remote_config(%Opamp.Proto.AgentConfigMap{config_map: desired})
      })
    end

    defp object(body), do: %Opamp.Proto.AgentConfigObject{body: body, content_type: "yaml"}

    test "keeps the other objects and replaces only the edited body" do
      agent =
        agent_with(%{
          "default/a" => %Opamp.Proto.AgentConfigObject{
            body: collector(%{"opentelemetry.io/opamp-managed" => "true"}),
            content_type: "yaml",
            role: "collector"
          },
          "default/b" => object(collector(%{"opentelemetry.io/opamp-managed" => "true"}))
        })

      %{config_map: config_map} = Agents.config_map_with(agent, "default/a", "new body")

      assert Map.keys(config_map) == ["default/a", "default/b"]
      assert config_map["default/a"].body == "new body"
      assert config_map["default/a"].content_type == "yaml"
      assert config_map["default/a"].role == "collector"
      assert config_map["default/b"] == agent.effective_config.config_map.config_map["default/b"]
    end

    test "leaves out collectors that the bridge does not manage" do
      agent =
        agent_with(%{
          "default/managed" => object(collector(%{"opentelemetry.io/opamp-managed" => "true"})),
          "default/by-bridge-name" =>
            object(collector(%{"opentelemetry.io/opamp-managed" => "opamp-bridge"})),
          "default/unlabeled" => object(collector(%{})),
          "default/disabled" => object(collector(%{"opentelemetry.io/opamp-managed" => "false"})),
          "default/reporting" =>
            object(
              collector(%{
                "opentelemetry.io/opamp-managed" => "true",
                "opentelemetry.io/opamp-reporting" => "true"
              })
            ),
          # Other agents report plain config bodies, which always stay.
          "" => object("receivers: {}"),
          "bad" => object(": not yaml : [")
        })

      %{config_map: config_map} = Agents.config_map_with(agent, "default/managed", "new body")

      assert Enum.sort(Map.keys(config_map)) ==
               ["", "bad", "default/by-bridge-name", "default/managed"]
    end

    test "includes the desired config, which wins over the effective config" do
      agent =
        agent_with(
          %{
            "default/a" => object(collector(%{"opentelemetry.io/opamp-managed" => "true"})),
            "default/b" => object("effective b")
          },
          %{
            "default/b" => object("desired b"),
            "default/not-applied-yet" => object("desired c")
          }
        )

      %{config_map: config_map} = Agents.config_map_with(agent, "default/a", "new body")

      assert config_map["default/b"].body == "desired b"
      assert config_map["default/not-applied-yet"].body == "desired c"
      assert config_map["default/a"].body == "new body"
    end
  end
end
