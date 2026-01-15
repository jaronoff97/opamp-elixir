defmodule OpAMPServer.OpAMP.EctoTypes do
  @moduledoc """
  Ecto type implementations for OpAMP protobuf messages.

  These types allow storing protobuf messages as binary in the database
  and automatically encoding/decoding them.
  """
end

defmodule OpAMPServer.OpAMP.EctoTypes.AgentDescription do
  @moduledoc """
  Ecto type for Opamp.Proto.AgentDescription.
  """

  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(term), do: {:ok, term}

  @impl true
  def load(term) when is_binary(term) do
    {:ok, Opamp.Proto.AgentDescription.decode(term)}
  end

  def load(nil), do: {:ok, nil}

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(%Opamp.Proto.AgentDescription{} = term) do
    {:ok, Opamp.Proto.AgentDescription.encode(term)}
  end

  def dump(_), do: :error
end

defmodule OpAMPServer.OpAMP.EctoTypes.ComponentHealth do
  @moduledoc """
  Ecto type for Opamp.Proto.ComponentHealth.
  """

  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(term), do: {:ok, term}

  @impl true
  def load(""), do: {:ok, nil}

  def load(term) when is_binary(term) do
    {:ok, Opamp.Proto.ComponentHealth.decode(term)}
  end

  def load(nil), do: {:ok, nil}

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(%Opamp.Proto.ComponentHealth{} = term) do
    {:ok, Opamp.Proto.ComponentHealth.encode(term)}
  end

  def dump(_), do: :error
end

defmodule OpAMPServer.OpAMP.EctoTypes.EffectiveConfig do
  @moduledoc """
  Ecto type for Opamp.Proto.EffectiveConfig.
  """

  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(term), do: {:ok, term}

  @impl true
  def load(term) when is_binary(term) do
    {:ok, Opamp.Proto.EffectiveConfig.decode(term)}
  end

  def load(nil), do: {:ok, nil}

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(%Opamp.Proto.EffectiveConfig{} = term) do
    {:ok, Opamp.Proto.EffectiveConfig.encode(term)}
  end

  def dump(_), do: :error
end

defmodule OpAMPServer.OpAMP.EctoTypes.RemoteConfigStatus do
  @moduledoc """
  Ecto type for Opamp.Proto.RemoteConfigStatus.
  """

  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(term), do: {:ok, term}

  @impl true
  def load(term) when is_binary(term) do
    {:ok, Opamp.Proto.RemoteConfigStatus.decode(term)}
  end

  def load(nil), do: {:ok, nil}

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(%Opamp.Proto.RemoteConfigStatus{} = term) do
    {:ok, Opamp.Proto.RemoteConfigStatus.encode(term)}
  end

  def dump(_), do: :error
end

defmodule OpAMPServer.OpAMP.EctoTypes.AgentRemoteConfig do
  @moduledoc """
  Ecto type for Opamp.Proto.AgentRemoteConfig.
  """

  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(term), do: {:ok, term}

  @impl true
  def load(term) when is_binary(term) do
    {:ok, Opamp.Proto.AgentRemoteConfig.decode(term)}
  end

  def load(nil), do: {:ok, nil}

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(%Opamp.Proto.AgentRemoteConfig{} = term) do
    {:ok, Opamp.Proto.AgentRemoteConfig.encode(term)}
  end

  def dump(_), do: :error
end
