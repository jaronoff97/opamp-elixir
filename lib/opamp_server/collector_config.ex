defmodule OpAMPServer.CollectorConfig do
  @moduledoc """
  Reads an OpenTelemetry Collector config from a config object body.

  The body is a collector config (`receivers:`, `service:` ...), or an
  `OpenTelemetryCollector` resource that holds one in `spec.config`, as the OpAMP
  Bridge reports it.
  """

  defstruct [:resource, config: %{}]

  @type t :: %__MODULE__{resource: map() | nil, config: map()}

  @sections ~w(receivers processors exporters connectors extensions)

  @doc "Parses a body. Returns `:error` if the body is not a YAML map."
  def parse(body) when is_binary(body) do
    case YamlElixir.read_from_string(body) do
      {:ok, %{"kind" => "OpenTelemetryCollector"} = resource} ->
        {:ok,
         %__MODULE__{resource: resource, config: get_in(resource, ["spec", "config"]) || %{}}}

      {:ok, %{} = config} ->
        {:ok, %__MODULE__{config: config}}

      _ ->
        :error
    end
  end

  def parse(_body), do: :error

  @doc "True if the body is an OpenTelemetryCollector resource."
  def resource?(%__MODULE__{resource: resource}), do: resource != nil

  @doc """
  True if the OpAMP Bridge can change this collector: it has the opamp-managed label and
  not `opamp-reporting: "true"`. A plain collector config is always manageable.
  """
  def managed?(%__MODULE__{resource: nil}), do: true

  def managed?(%__MODULE__{resource: resource}) do
    labels = get_in(resource, ["metadata", "labels"]) || %{}
    label = &String.downcase(to_string(labels[&1]))

    label.("opentelemetry.io/opamp-managed") not in ["", "false"] and
      label.("opentelemetry.io/opamp-reporting") != "true"
  end

  @doc "The metadata.name and metadata.namespace of a resource, or nil."
  def name(%__MODULE__{resource: nil}), do: nil
  def name(%__MODULE__{resource: resource}), do: get_in(resource, ["metadata", "name"])
  def namespace(%__MODULE__{resource: nil}), do: nil
  def namespace(%__MODULE__{resource: resource}), do: get_in(resource, ["metadata", "namespace"])

  @doc "The component names of a section, for example `\"receivers\"`."
  def components(%__MODULE__{config: config}, section) when section in @sections do
    case config[section] do
      %{} = components -> components |> Map.keys() |> Enum.sort()
      _ -> []
    end
  end

  @doc """
  The pipelines in `service.pipelines`, sorted by name. Each is
  `%{name: "traces", receivers: [...], processors: [...], exporters: [...]}`.
  """
  def pipelines(%__MODULE__{config: config}) do
    case get_in(config, ["service", "pipelines"]) do
      %{} = pipelines ->
        for {name, pipeline} <- Enum.sort(pipelines), is_map(pipeline) do
          %{
            name: name,
            receivers: List.wrap(pipeline["receivers"]),
            processors: List.wrap(pipeline["processors"]),
            exporters: List.wrap(pipeline["exporters"])
          }
        end

      _ ->
        []
    end
  end

  @doc "The signal of a pipeline name: `\"traces/2\"` is `\"traces\"`."
  def signal(pipeline_name), do: pipeline_name |> String.split("/") |> hd()
end
