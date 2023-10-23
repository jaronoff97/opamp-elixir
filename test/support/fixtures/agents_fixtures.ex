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
        effective_config: %{},
        instance_id: "some instance_id"
      })
      |> OpAMPServer.Agents.create_agent()

    agent
  end
end
