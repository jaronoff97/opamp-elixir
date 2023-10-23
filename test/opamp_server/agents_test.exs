defmodule OpAMPServer.AgentsTest do
  use OpAMPServer.DataCase

  alias OpAMPServer.Agents

  describe "agent" do
    alias OpAMPServer.Agents.Agent

    import OpAMPServer.AgentsFixtures

    @invalid_attrs %{instance_id: nil, effective_config: nil}

    test "list_agent/0 returns all agent" do
      agent = agent_fixture()
      assert Agents.list_agent() == [agent]
    end

    test "get_agent!/1 returns the agent with given id" do
      agent = agent_fixture()
      assert Agents.get_agent!(agent.id) == agent
    end

    test "create_agent/1 with valid data creates a agent" do
      valid_attrs = %{instance_id: "some instance_id", effective_config: %{}}

      assert {:ok, %Agent{} = agent} = Agents.create_agent(valid_attrs)
      assert agent.instance_id == "some instance_id"
      assert agent.effective_config == %{}
    end

    test "create_agent/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Agents.create_agent(@invalid_attrs)
    end

    test "update_agent/2 with valid data updates the agent" do
      agent = agent_fixture()
      update_attrs = %{instance_id: "some updated instance_id", effective_config: %{}}

      assert {:ok, %Agent{} = agent} = Agents.update_agent(agent, update_attrs)
      assert agent.instance_id == "some updated instance_id"
      assert agent.effective_config == %{}
    end

    test "update_agent/2 with invalid data returns error changeset" do
      agent = agent_fixture()
      assert {:error, %Ecto.Changeset{}} = Agents.update_agent(agent, @invalid_attrs)
      assert agent == Agents.get_agent!(agent.id)
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
