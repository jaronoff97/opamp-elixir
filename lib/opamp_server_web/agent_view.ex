defmodule OpAMPServerWeb.AgentView do
  @moduledoc """
  Display values for an `OpAMPServer.Agents.Agent`: its name, attributes, status,
  capabilities and config objects. Pure functions, so every page shows an agent the same
  way, and an agent that has not reported a field still renders.
  """

  import Bitwise

  alias OpAMPServer.CollectorConfig
  alias OpAMPServer.OpAMP.Protocol.Helpers

  @doc "The service.name attribute, or a short form of the instance uid."
  def name(agent),
    do: attribute(agent, "service.name") || "agent " <> String.slice(agent.id, 0, 8)

  @doc "An identifying or non-identifying attribute as a string, or nil."
  def attribute(agent, key) do
    Enum.find_value(attributes(agent, :identifying) ++ attributes(agent, :non_identifying), fn
      {^key, value} -> value
      _ -> nil
    end)
  end

  @doc "The identifying or non-identifying attributes as `{key, string}`, sorted by key."
  def attributes(%{description: nil}, _kind), do: []

  def attributes(%{description: description}, kind) do
    attributes =
      case kind do
        :identifying -> description.identifying_attributes
        :non_identifying -> description.non_identifying_attributes
      end

    (attributes || [])
    |> Enum.map(&{&1.key, display(Helpers.clean_any_value(&1.value, cast_string: true))})
    |> Enum.sort()
  end

  defp display(value) when is_binary(value), do: value
  defp display(value) when is_list(value) or is_map(value), do: Jason.encode!(value)
  defp display(value), do: to_string(value)

  @doc """
  `:healthy`, `:unhealthy` or `:unknown`. An agent reports health only with the
  ReportsHealth capability.
  """
  def status(%{component_health: nil}), do: :unknown
  def status(%{component_health: %{healthy: true}}), do: :healthy
  def status(%{component_health: _}), do: :unhealthy

  @doc "The last error that the agent reported, or nil."
  def last_error(%{component_health: %{last_error: error}}) when error not in [nil, ""], do: error
  def last_error(_agent), do: nil

  @doc "The capability names that the agent reported, without the prefix, in bit order."
  def capabilities(%{capabilities: nil}), do: []

  def capabilities(%{capabilities: bits}) do
    for {key, bit} <- Enum.sort_by(Opamp.Proto.AgentCapabilities.mapping(), &elem(&1, 1)),
        bit != 0 and (bits &&& bit) != 0,
        do: key |> Atom.to_string() |> String.replace_prefix("AgentCapabilities_", "")
  end

  @doc """
  The agent's config objects, sorted by key. Each is a map with `:key`, `:object` (the
  AgentConfigObject), `:config` (a parsed `CollectorConfig`, or nil), `:resource?`,
  `:managed?` and `:health` (the ComponentHealth with the same key, or nil).
  """
  def config_objects(agent) do
    objects =
      case agent.effective_config do
        %{config_map: %{config_map: objects}} -> objects
        _ -> %{}
      end

    health_map =
      case agent.component_health do
        %{component_health_map: map} -> map
        _ -> %{}
      end

    for {key, object} <- Enum.sort(objects) do
      config =
        case CollectorConfig.parse(object.body) do
          {:ok, config} -> config
          :error -> nil
        end

      %{
        key: key,
        object: object,
        config: config,
        resource?: config != nil and CollectorConfig.resource?(config),
        managed?: config != nil and CollectorConfig.managed?(config),
        health: health_map[key]
      }
    end
  end

  @doc """
  `:bridge` if the agent reports OpenTelemetryCollector resources (the OpAMP Bridge),
  otherwise `:agent`.
  """
  def kind(agent) do
    if Enum.any?(config_objects(agent), & &1.resource?), do: :bridge, else: :agent
  end

  @doc "`{ready, total}` pods of a collector, from its ComponentHealth."
  def pods(%{component_health_map: pods}) when map_size(pods) > 0,
    do: {Enum.count(pods, fn {_name, pod} -> pod.healthy end), map_size(pods)}

  def pods(_health), do: {0, 0}

  @doc """
  The remote config state: `{:none, nil}` without a desired config, or `{status, message}`
  where status is `:applied`, `:applying`, `:failed` or `:pending` (sent, no status yet).
  """
  def remote_config(%{desired_remote_config: nil}), do: {:none, nil}

  def remote_config(%{desired_remote_config: desired, remote_config_status: status}) do
    case status do
      %{last_remote_config_hash: hash, status: state, error_message: message}
      when hash == desired.config_hash ->
        case state do
          :RemoteConfigStatuses_APPLIED -> {:applied, nil}
          :RemoteConfigStatuses_APPLYING -> {:applying, nil}
          :RemoteConfigStatuses_FAILED -> {:failed, message}
          _ -> {:pending, nil}
        end

      _ ->
        {:pending, nil}
    end
  end

  @doc "A short relative time: \"just now\", \"12s ago\", \"5m ago\", \"3h ago\", \"2d ago\"."
  def ago(nil, _now), do: "never"

  def ago(%DateTime{} = time, now) do
    case DateTime.diff(now, time) do
      s when s < 5 -> "just now"
      s when s < 60 -> "#{s}s ago"
      s when s < 3600 -> "#{div(s, 60)}m ago"
      s when s < 86_400 -> "#{div(s, 3600)}h ago"
      s -> "#{div(s, 86_400)}d ago"
    end
  end

  @doc """
  The subject, issuer and validity of a certificate (PEM or an X509 OTP certificate),
  or nil if it does not parse.
  """
  def certificate_summary(pem) when is_binary(pem) do
    case X509.Certificate.from_pem(pem) do
      {:ok, certificate} -> certificate_summary(certificate)
      {:error, _} -> nil
    end
  end

  def certificate_summary(certificate) do
    {:Validity, not_before, not_after} = X509.Certificate.validity(certificate)

    %{
      subject: X509.RDNSequence.to_string(X509.Certificate.subject(certificate)),
      issuer: X509.RDNSequence.to_string(X509.Certificate.issuer(certificate)),
      not_before: X509.DateTime.to_datetime(not_before),
      not_after: X509.DateTime.to_datetime(not_after)
    }
  end

  @doc "The parts of a ConnectionSettingsOffers, as `{label, destination}`."
  def offer_parts(nil), do: []

  def offer_parts(offer) do
    parts = [
      opamp: "OpAMP",
      own_metrics: "Own metrics",
      own_traces: "Own traces",
      own_logs: "Own logs"
    ]

    named =
      for {key, label} <- parts, settings = Map.get(offer, key) do
        {label, blank_as_dash(settings.destination_endpoint)}
      end

    named ++
      for {name, settings} <- Enum.sort(offer.other_connections || %{}),
          do: {name, blank_as_dash(settings.destination_endpoint)}
  end

  defp blank_as_dash(value) when value in [nil, ""], do: "—"
  defp blank_as_dash(value), do: value
end
