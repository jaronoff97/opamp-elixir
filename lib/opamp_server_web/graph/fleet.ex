defmodule OpAMPServerWeb.Graph.Fleet do
  @moduledoc """
  The fleet graph: this server, each connected agent, and each collector resource that
  an agent (the OpAMP Bridge) reports.

  Node ids: `"server"`, `"agent:<instance uid>"` and `"collector:<instance uid>:<config key>"`.
  An agent node holds the Agent, a collector node holds its `AgentView.config_objects/1` entry
  with an `:agent_id`.
  """

  alias OpAMPServerWeb.{AgentView, Graph}
  alias OpAMPServerWeb.Graph.Layout

  def build(agents) do
    server =
      Graph.add_node(Graph.new(), "server", :server,
        data: %{agents: length(agents)},
        width: 208,
        height: 64
      )

    agents
    |> Enum.sort_by(&AgentView.name/1)
    |> Enum.reduce(server, &add_agent/2)
    |> Layout.layered()
  end

  defp add_agent(agent, graph) do
    id = "agent:" <> agent.id

    graph =
      graph
      |> Graph.add_node(id, :agent, data: agent, width: 288, height: 84)
      |> Graph.add_edge("server", id)

    for object <- AgentView.config_objects(agent), object.resource?, reduce: graph do
      graph ->
        collector = "collector:#{agent.id}:#{object.key}"

        graph
        |> Graph.add_node(collector, :collector,
          data: Map.put(object, :agent_id, agent.id),
          width: 240,
          height: 72
        )
        |> Graph.add_edge(id, collector)
    end
  end
end
