defmodule OpAMPServerWeb.Graph.BuildersTest do
  use ExUnit.Case, async: true

  import OpAMPServer.AgentsFixtures, only: [collector_body: 1]

  alias OpAMPServer.Agents.Agent
  alias OpAMPServer.CollectorConfig
  alias OpAMPServerWeb.Graph
  alias OpAMPServerWeb.Graph.{Fleet, Pipeline}

  defp ids(graph), do: graph.nodes |> Enum.map(& &1.id) |> Enum.sort()
  defp edges(graph), do: graph.edges |> Enum.map(&{&1.from, &1.to}) |> Enum.sort()

  defp agent(id, name, objects \\ %{}) do
    %Agent{
      id: id,
      description: %Opamp.Proto.AgentDescription{
        identifying_attributes: [
          %Opamp.Proto.KeyValue{
            key: "service.name",
            value: %Opamp.Proto.AnyValue{value: {:string_value, name}}
          }
        ]
      },
      effective_config: %Opamp.Proto.EffectiveConfig{
        config_map: %Opamp.Proto.AgentConfigMap{
          config_map:
            Map.new(objects, fn {k, body} -> {k, %Opamp.Proto.AgentConfigObject{body: body}} end)
        }
      }
    }
  end

  describe "Fleet.build/1" do
    test "links the server to each agent, and each bridge to its collectors" do
      graph =
        Fleet.build([
          agent("b", "bridge", %{
            "default/a" => collector_body("a"),
            "default/b" => collector_body("b")
          }),
          agent("c", "collector", %{"" => "receivers: {}"})
        ])

      assert ids(graph) ==
               ["agent:b", "agent:c", "collector:b:default/a", "collector:b:default/b", "server"]

      assert edges(graph) == [
               {"agent:b", "collector:b:default/a"},
               {"agent:b", "collector:b:default/b"},
               {"server", "agent:b"},
               {"server", "agent:c"}
             ]

      assert Graph.node(graph, "server").data == %{agents: 2}

      assert %{key: "default/a", agent_id: "b", managed?: true} =
               Graph.node(graph, "collector:b:default/a").data
    end

    test "places the server, the agents and the collectors in three columns" do
      graph = Fleet.build([agent("b", "bridge", %{"default/a" => collector_body("a")})])

      assert Enum.map(~w(server agent:b collector:b:default/a), &Graph.node(graph, &1).rank) == [
               0,
               1,
               2
             ]

      assert graph.width > 0 and graph.height > 0
    end

    test "orders the agents by name" do
      graph = Fleet.build([agent("z", "zeta"), agent("a", "alpha")])

      assert Graph.node(graph, "agent:a").y < Graph.node(graph, "agent:z").y
    end

    test "with no agents, it shows only the server" do
      assert ids(Fleet.build([])) == ["server"]
    end
  end

  describe "Pipeline.build/1" do
    defp pipeline(yaml) do
      {:ok, config} = CollectorConfig.parse(yaml)
      Pipeline.build(config)
    end

    test "chains receivers, processors and exporters" do
      graph =
        pipeline("""
        service:
          pipelines:
            traces:
              receivers: [otlp]
              processors: [memory_limiter, batch]
              exporters: [debug, otlphttp]
        """)

      assert edges(graph) == [
               {"processor:traces:batch", "exporter:debug"},
               {"processor:traces:batch", "exporter:otlphttp"},
               {"processor:traces:memory_limiter", "processor:traces:batch"},
               {"receiver:otlp", "processor:traces:memory_limiter"}
             ]

      assert %{name: "batch", kind: :processor, signals: ["traces"]} =
               Graph.node(graph, "processor:traces:batch").data
    end

    test "shares receivers and exporters between pipelines, with all their signals" do
      graph =
        pipeline("""
        service:
          pipelines:
            traces: {receivers: [otlp], processors: [batch], exporters: [debug]}
            metrics: {receivers: [otlp], exporters: [debug]}
        """)

      assert ids(graph) ==
               ["exporter:debug", "processor:traces:batch", "receiver:otlp"]

      assert {"receiver:otlp", "exporter:debug"} in edges(graph)
      assert Graph.node(graph, "receiver:otlp").data.signals == ["metrics", "traces"]
    end

    test "puts every exporter in the last column" do
      graph =
        pipeline("""
        service:
          pipelines:
            traces: {receivers: [otlp], processors: [a, b], exporters: [debug]}
            logs: {receivers: [filelog], exporters: [otlphttp]}
        """)

      assert Graph.node(graph, "exporter:otlphttp").rank ==
               Graph.node(graph, "exporter:debug").rank
    end

    test "a connector links the pipelines that it joins" do
      graph =
        pipeline("""
        connectors: {spanmetrics: {}}
        service:
          pipelines:
            traces: {receivers: [otlp], exporters: [spanmetrics]}
            metrics: {receivers: [spanmetrics], exporters: [debug]}
        """)

      assert {"receiver:otlp", "connector:spanmetrics"} in edges(graph)
      assert {"connector:spanmetrics", "exporter:debug"} in edges(graph)
      assert Graph.node(graph, "connector:spanmetrics").data.kind == :connector
    end

    test "a config without pipelines is an empty graph" do
      assert pipeline("receivers: {otlp: {}}").nodes == []
    end
  end
end
