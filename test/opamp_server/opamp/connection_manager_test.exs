defmodule OpAMPServer.OpAMP.ConnectionManagerTest do
  use ExUnit.Case, async: true
  use OpAMPServer.OpAMPCase

  alias OpAMPServer.OpAMP.ConnectionManager

  setup do
    # Start a unique ConnectionManager for each test
    name = :"connection_manager_#{System.unique_integer([:positive])}"
    {:ok, pid} = ConnectionManager.start_link(name: name)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    %{manager: name}
  end

  describe "start_link/1" do
    test "starts the connection manager" do
      name = :"test_manager_#{System.unique_integer([:positive])}"
      assert {:ok, pid} = ConnectionManager.start_link(name: name)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with empty connections" do
      name = :"test_manager_#{System.unique_integer([:positive])}"
      {:ok, _pid} = ConnectionManager.start_link(name: name)

      assert ConnectionManager.list_connections(name) == []
      assert ConnectionManager.connection_count(name) == 0
    end
  end

  describe "is_new_connection?/2" do
    test "returns true for unregistered agent", %{manager: manager} do
      agent_id = generate_instance_uid_string()

      assert ConnectionManager.is_new_connection?(agent_id, manager) == true
    end

    test "returns false for registered agent", %{manager: manager} do
      agent_id = generate_instance_uid_string()
      ConnectionManager.register(agent_id, manager)

      assert ConnectionManager.is_new_connection?(agent_id, manager) == false
    end

    test "returns true after agent is unregistered", %{manager: manager} do
      agent_id = generate_instance_uid_string()
      ConnectionManager.register(agent_id, manager)
      ConnectionManager.unregister(agent_id, manager)

      # Give cast time to process
      Process.sleep(10)

      assert ConnectionManager.is_new_connection?(agent_id, manager) == true
    end
  end

  describe "register/2" do
    test "registers a new agent", %{manager: manager} do
      agent_id = generate_instance_uid_string()

      assert :ok = ConnectionManager.register(agent_id, manager)
      assert ConnectionManager.connected?(agent_id, manager) == true
    end

    test "allows registering the same agent multiple times", %{manager: manager} do
      agent_id = generate_instance_uid_string()

      assert :ok = ConnectionManager.register(agent_id, manager)
      assert :ok = ConnectionManager.register(agent_id, manager)
      assert ConnectionManager.connection_count(manager) == 1
    end

    test "registers multiple different agents", %{manager: manager} do
      agent_ids = for _ <- 1..5, do: generate_instance_uid_string()

      Enum.each(agent_ids, fn id ->
        ConnectionManager.register(id, manager)
      end)

      assert ConnectionManager.connection_count(manager) == 5
    end
  end

  describe "unregister/2" do
    test "unregisters a connected agent", %{manager: manager} do
      agent_id = generate_instance_uid_string()
      ConnectionManager.register(agent_id, manager)

      ConnectionManager.unregister(agent_id, manager)
      # Allow cast to process
      Process.sleep(10)

      assert ConnectionManager.connected?(agent_id, manager) == false
    end

    test "handles unregistering non-existent agent gracefully", %{manager: manager} do
      agent_id = generate_instance_uid_string()

      # Should not raise
      ConnectionManager.unregister(agent_id, manager)
      Process.sleep(10)

      assert ConnectionManager.connected?(agent_id, manager) == false
    end

    test "unregistering one agent does not affect others", %{manager: manager} do
      agent1 = generate_instance_uid_string()
      agent2 = generate_instance_uid_string()

      ConnectionManager.register(agent1, manager)
      ConnectionManager.register(agent2, manager)
      ConnectionManager.unregister(agent1, manager)
      Process.sleep(10)

      assert ConnectionManager.connected?(agent1, manager) == false
      assert ConnectionManager.connected?(agent2, manager) == true
    end
  end

  describe "connected?/2" do
    test "returns false for unknown agent", %{manager: manager} do
      agent_id = generate_instance_uid_string()

      assert ConnectionManager.connected?(agent_id, manager) == false
    end

    test "returns true for registered agent", %{manager: manager} do
      agent_id = generate_instance_uid_string()
      ConnectionManager.register(agent_id, manager)

      assert ConnectionManager.connected?(agent_id, manager) == true
    end
  end

  describe "list_connections/1" do
    test "returns empty list when no connections", %{manager: manager} do
      assert ConnectionManager.list_connections(manager) == []
    end

    test "returns all connected agents", %{manager: manager} do
      agent_ids = for _ <- 1..3, do: generate_instance_uid_string()

      Enum.each(agent_ids, fn id ->
        ConnectionManager.register(id, manager)
      end)

      connections = ConnectionManager.list_connections(manager)

      assert length(connections) == 3
      assert Enum.sort(connections) == Enum.sort(agent_ids)
    end

    test "does not include unregistered agents", %{manager: manager} do
      agent1 = generate_instance_uid_string()
      agent2 = generate_instance_uid_string()

      ConnectionManager.register(agent1, manager)
      ConnectionManager.register(agent2, manager)
      ConnectionManager.unregister(agent1, manager)
      Process.sleep(10)

      connections = ConnectionManager.list_connections(manager)

      assert connections == [agent2]
    end
  end

  describe "connection_count/1" do
    test "returns 0 when no connections", %{manager: manager} do
      assert ConnectionManager.connection_count(manager) == 0
    end

    test "returns correct count", %{manager: manager} do
      for _ <- 1..10 do
        ConnectionManager.register(generate_instance_uid_string(), manager)
      end

      assert ConnectionManager.connection_count(manager) == 10
    end

    test "decrements when agents disconnect", %{manager: manager} do
      agents = for _ <- 1..5, do: generate_instance_uid_string()

      Enum.each(agents, fn id ->
        ConnectionManager.register(id, manager)
      end)

      assert ConnectionManager.connection_count(manager) == 5

      ConnectionManager.unregister(hd(agents), manager)
      Process.sleep(10)

      assert ConnectionManager.connection_count(manager) == 4
    end
  end

  describe "concurrent access" do
    test "handles concurrent registrations", %{manager: manager} do
      agent_ids = for _ <- 1..100, do: generate_instance_uid_string()

      # Register concurrently
      tasks =
        Enum.map(agent_ids, fn id ->
          Task.async(fn ->
            ConnectionManager.register(id, manager)
          end)
        end)

      Task.await_many(tasks)

      assert ConnectionManager.connection_count(manager) == 100
    end

    test "handles concurrent is_new_connection? checks", %{manager: manager} do
      agent_id = generate_instance_uid_string()

      # Check concurrently before registration
      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            ConnectionManager.is_new_connection?(agent_id, manager)
          end)
        end

      results = Task.await_many(tasks)

      # All should return true since agent wasn't registered
      assert Enum.all?(results, & &1)
    end

    test "handles mixed concurrent operations", %{manager: manager} do
      agents = for _ <- 1..20, do: generate_instance_uid_string()

      # Mix of operations
      tasks =
        Enum.flat_map(agents, fn id ->
          [
            Task.async(fn -> ConnectionManager.register(id, manager) end),
            Task.async(fn -> ConnectionManager.is_new_connection?(id, manager) end),
            Task.async(fn -> ConnectionManager.connected?(id, manager) end)
          ]
        end)

      # Should complete without errors
      Task.await_many(tasks)

      # All agents should be registered at the end
      assert ConnectionManager.connection_count(manager) == 20
    end
  end

  describe "edge cases" do
    test "handles empty string agent_id", %{manager: manager} do
      ConnectionManager.register("", manager)

      assert ConnectionManager.connected?("", manager) == true
      assert ConnectionManager.connection_count(manager) == 1
    end

    test "handles very long agent_id", %{manager: manager} do
      long_id = String.duplicate("a", 1000)
      ConnectionManager.register(long_id, manager)

      assert ConnectionManager.connected?(long_id, manager) == true
    end

    test "handles special characters in agent_id", %{manager: manager} do
      special_id = "agent-123_test.example:8080/path"
      ConnectionManager.register(special_id, manager)

      assert ConnectionManager.connected?(special_id, manager) == true
    end
  end
end
