defmodule OpAMPServerWeb.Graph.Pipeline do
  @moduledoc """
  The graph of a collector config: receivers, then the processors of each pipeline, then
  exporters.

  Receivers and exporters are shared between pipelines, as in the collector. Each pipeline
  has its own processor chain, so a processor node is `"processor:<pipeline>:<name>"`. A
  connector is one node that is an exporter of one pipeline and a receiver of another.
  Each node's data is `%{name, kind, signals}`, where signals are the pipeline signals that
  use it (`"traces"`, `"metrics"`, `"logs"`).
  """

  alias OpAMPServer.CollectorConfig
  alias OpAMPServerWeb.Graph
  alias OpAMPServerWeb.Graph.Layout

  def build(%CollectorConfig{} = config) do
    connectors = MapSet.new(CollectorConfig.components(config, "connectors"))
    pipelines = CollectorConfig.pipelines(config)

    # Each pipeline as stages: [receivers], [processor], ..., [exporters].
    staged =
      for pipeline <- pipelines do
        signal = CollectorConfig.signal(pipeline.name)
        component = &component(&1, &2, connectors, signal)

        stages =
          [Enum.map(pipeline.receivers, &component.(:receiver, &1))] ++
            Enum.map(pipeline.processors, &[component.({:processor, pipeline.name}, &1)]) ++
            [Enum.map(pipeline.exporters, &component.(:exporter, &1))]

        Enum.reject(stages, &(&1 == []))
      end

    # A node used by many pipelines lists all their signals.
    nodes = staged |> List.flatten() |> merge_signals()

    graph =
      Enum.reduce(nodes, Graph.new(), fn {id, data}, graph ->
        Graph.add_node(graph, id, data.kind, data: data, width: 200, height: 56)
      end)

    staged
    |> Enum.reduce(graph, fn stages, graph ->
      stages
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(graph, fn [from, to], graph ->
        for {a, _} <- from,
            {b, _} <- to,
            reduce: graph,
            do: (graph -> Graph.add_edge(graph, a, b))
      end)
    end)
    |> Layout.layered(align_sinks: true)
  end

  defp component(role, name, connectors, signal) do
    {kind, id} =
      cond do
        role in [:receiver, :exporter] and name in connectors -> {:connector, "connector:#{name}"}
        role == :receiver -> {:receiver, "receiver:#{name}"}
        role == :exporter -> {:exporter, "exporter:#{name}"}
        true -> {:processor, "processor:#{elem(role, 1)}:#{name}"}
      end

    {id, %{name: name, kind: kind, signals: [signal]}}
  end

  # Keeps the first position of each node, with the signals of every pipeline that uses it.
  defp merge_signals(components) do
    signals =
      Enum.reduce(components, %{}, fn {id, data}, acc ->
        Map.update(acc, id, data.signals, &Enum.uniq(&1 ++ data.signals))
      end)

    components
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.map(fn {id, data} -> {id, %{data | signals: Enum.sort(signals[id])}} end)
  end
end
