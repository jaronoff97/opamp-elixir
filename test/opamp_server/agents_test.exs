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
      assert agent.id != nil
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
end
