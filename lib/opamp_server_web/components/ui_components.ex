defmodule OpAMPServerWeb.UIComponents do
  @moduledoc """
  Small components that every page uses: status badges and dots, stat cards, key/value
  lists, cards and empty states. They take display values from `OpAMPServerWeb.AgentView`.
  """
  use Phoenix.Component

  @status %{
    healthy: {"Healthy", "badge-success", "bg-success"},
    unhealthy: {"Unhealthy", "badge-error", "bg-error"},
    unknown: {"Unknown", "badge-ghost", "bg-base-content/30"},
    applied: {"Applied", "badge-success", "bg-success"},
    applying: {"Applying", "badge-warning", "bg-warning"},
    pending: {"Pending", "badge-warning", "bg-warning"},
    failed: {"Failed", "badge-error", "bg-error"},
    none: {"No remote config", "badge-ghost", "bg-base-content/30"}
  }

  @doc "A colored badge for a status from `AgentView.status/1` or `AgentView.remote_config/1`."
  attr :status, :atom, required: true
  attr :label, :string, default: nil, doc: "overrides the default label"
  attr :class, :any, default: nil

  def status_badge(assigns) do
    {label, badge, dot} = Map.fetch!(@status, assigns.status)
    assigns = assign(assigns, label: assigns.label || label, badge: badge, dot: dot)

    ~H"""
    <span class={["badge badge-sm badge-soft gap-1.5 whitespace-nowrap", @badge, @class]}>
      <span class={["size-1.5 rounded-full", @dot]} />{@label}
    </span>
    """
  end

  @doc "A status dot, with the label for screen readers."
  attr :status, :atom, required: true
  attr :class, :any, default: nil

  def status_dot(assigns) do
    {label, _badge, dot} = Map.fetch!(@status, assigns.status)
    assigns = assign(assigns, label: label, dot: dot)

    ~H"""
    <span class={["relative inline-flex size-2.5 shrink-0", @class]} title={@label}>
      <span
        :if={@status == :healthy}
        class={["absolute inset-0 rounded-full opacity-60 motion-safe:animate-ping", @dot]}
      />
      <span class={["relative size-2.5 rounded-full", @dot]} />
      <span class="sr-only">{@label}</span>
    </span>
    """
  end

  @doc "A number with a label, for the summary row of a page."
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :tone, :string, default: "text-primary"

  def stat_card(assigns) do
    ~H"""
    <div class="card card-border bg-base-100">
      <div class="card-body flex-row items-center gap-4 p-4">
        <span class={["grid size-10 place-items-center rounded-field bg-base-200", @tone]}>
          <span class={[@icon, "size-5"]} />
        </span>
        <div>
          <div class="text-2xl font-semibold leading-none tabular-nums">{@value}</div>
          <div class="mt-1 text-xs text-base-content/60">{@label}</div>
        </div>
      </div>
    </div>
    """
  end

  @doc "A titled card."
  attr :title, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true
  slot :actions

  def card(assigns) do
    ~H"""
    <section class={["card card-border bg-base-100", @class]} {@rest}>
      <div class="card-body gap-3 p-5">
        <div :if={@title || @actions != []} class="flex items-center justify-between gap-2">
          <h2 :if={@title} class="text-sm font-semibold">{@title}</h2>
          <div class="flex items-center gap-2">{render_slot(@actions)}</div>
        </div>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc "A list of `{key, value}` pairs, or an empty message."
  attr :items, :list, required: true
  attr :empty, :string, default: "Nothing reported."

  def kv_list(assigns) do
    ~H"""
    <p :if={@items == []} class="text-sm text-base-content/60">{@empty}</p>
    <dl
      :if={@items != []}
      class="grid grid-cols-[minmax(0,2fr)_minmax(0,3fr)] gap-x-4 gap-y-2 text-sm"
    >
      <%= for {key, value} <- @items do %>
        <dt class="truncate font-mono text-xs leading-5 text-base-content/60" title={key}>{key}</dt>
        <dd class="break-all">{value}</dd>
      <% end %>
    </dl>
    """
  end

  @doc "A message with an icon, for a list or a graph without content."
  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 px-6 py-10 text-center">
      <span class={[@icon, "size-8 text-base-content/30"]} />
      <p class="font-medium">{@title}</p>
      <p class="max-w-sm text-sm text-base-content/60">{render_slot(@inner_block)}</p>
    </div>
    """
  end
end
