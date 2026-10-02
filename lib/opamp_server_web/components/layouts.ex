defmodule OpAMPServerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use OpAMPServerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  The app shell: a sidebar with the main sections and the page content. On small
  screens the sidebar is a drawer that the menu button opens.

      <Layouts.app flash={@flash} current={:agents}>
        ...
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current, :atom, required: true, doc: "the active section: :fleet, :agents or :settings"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="nav-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content flex min-h-screen min-w-0 flex-col bg-base-200">
        <header class="navbar border-b border-base-300 bg-base-100 lg:hidden">
          <label for="nav-drawer" class="btn btn-square btn-ghost" aria-label="Open the menu">
            <.icon name="hero-bars-3" class="size-5" />
          </label>
          <.brand />
        </header>
        <main class="mx-auto w-full max-w-7xl flex-1 px-4 py-6 sm:px-8">
          {render_slot(@inner_block)}
        </main>
      </div>
      <div class="drawer-side z-40">
        <label for="nav-drawer" class="drawer-overlay" aria-label="Close the menu"></label>
        <aside class="flex min-h-full w-60 flex-col border-r border-base-300 bg-base-100">
          <div class="px-5 py-5"><.brand /></div>
          <nav aria-label="Main">
            <ul class="menu w-full gap-1 px-3">
              <.nav_item to={~p"/"} icon="hero-share" label="Fleet" active={@current == :fleet} />
              <.nav_item
                to={~p"/agents"}
                icon="hero-server-stack"
                label="Agents"
                active={@current == :agents}
              />
              <.nav_item
                to={~p"/settings"}
                icon="hero-cog-6-tooth"
                label="Settings"
                active={@current == :settings}
              />
            </ul>
          </nav>
          <div class="mt-auto flex items-center justify-between gap-2 border-t border-base-300 px-5 py-4">
            <a
              href="https://github.com/jaronoff97/opamp-elixir"
              class="link link-hover text-xs text-base-content/60"
            >
              GitHub
            </a>
            <.theme_toggle />
          </div>
        </aside>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp brand(assigns) do
    ~H"""
    <a href={~p"/"} class="flex items-center gap-2.5">
      <img src={~p"/images/otel.svg"} width="28" alt="" />
      <span class="leading-tight">
        <span class="block text-sm font-semibold">opamp-elixir</span>
        <span class="block text-xs text-base-content/60">OpAMP server</span>
      </span>
    </a>
    """
  end

  attr :to, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp nav_item(assigns) do
    ~H"""
    <li>
      <.link
        navigate={@to}
        class={[@active && "menu-active"]}
        aria-current={if @active, do: "page", else: "false"}
      >
        <.icon name={@icon} class="size-4" />{@label}
      </.link>
    </li>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
