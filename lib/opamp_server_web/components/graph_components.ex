defmodule OpAMPServerWeb.GraphComponents do
  @moduledoc """
  Renders an `OpAMPServerWeb.Graph` after `OpAMPServerWeb.Graph.Layout` placed it.

  The nodes are HTML, so each page renders its own node cards through the `:node` slot.
  The edges are one SVG layer under the nodes. A colocated hook adds pan (drag the
  background), zoom (wheel or the buttons) and fit to view.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias OpAMPServerWeb.Graph

  attr :id, :string, required: true
  attr :graph, Graph, required: true, doc: "a graph with positions, from Graph.Layout"
  attr :selected, :any, default: nil, doc: "the id of the selected node"

  attr :on_select, :any,
    default: nil,
    doc: "the phx-click event for a node click, with the node id as phx-value-id"

  attr :class, :any, default: "h-[32rem]"

  slot :node, required: true, doc: "renders one node; receives the Graph.Node"
  slot :empty, doc: "shown when the graph has no nodes"

  def graph(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".GraphViewport"
      data-width={@graph.width}
      data-height={@graph.height}
      class={[
        "relative overflow-hidden rounded-box border border-base-300 bg-base-200/50",
        "select-none touch-none cursor-grab active:cursor-grabbing",
        @class
      ]}
    >
      <div
        :if={@graph.nodes == []}
        class="absolute inset-0 grid place-items-center text-sm text-base-content/60"
      >
        {render_slot(@empty)}
      </div>

      <div id={"#{@id}-viewport"} data-graph-viewport class="absolute left-0 top-0 origin-top-left">
        <svg
          width={@graph.width}
          height={@graph.height}
          class="absolute left-0 top-0 overflow-visible pointer-events-none"
          aria-hidden="true"
        >
          <path
            :for={edge <- @graph.edges}
            id={"#{@id}-edge-#{edge.id}"}
            d={edge.path}
            class={[
              "fill-none transition-[stroke] duration-300",
              if(@selected in [edge.from, edge.to],
                do: "stroke-primary",
                else: "stroke-base-content/25"
              )
            ]}
            stroke-width="1.5"
          />
        </svg>

        <div
          :for={node <- @graph.nodes}
          id={"#{@id}-node-#{node.id}"}
          data-graph-node
          class="absolute transition-[left,top] duration-300 cursor-default"
          style={"left: #{node.x}px; top: #{node.y}px; width: #{node.width}px; height: #{node.height}px"}
        >
          <button
            :if={@on_select}
            type="button"
            phx-click={@on_select}
            phx-value-id={node.id}
            aria-pressed={to_string(node.id == @selected)}
            class={[
              "size-full text-left rounded-box cursor-pointer",
              "focus-visible:outline-2 focus-visible:outline-primary",
              node.id == @selected && "ring-2 ring-primary ring-offset-2 ring-offset-base-200"
            ]}
          >
            {render_slot(@node, node)}
          </button>
          <div :if={!@on_select} class="size-full">{render_slot(@node, node)}</div>
        </div>
      </div>

      <div data-graph-controls class="absolute bottom-3 right-3 join shadow-sm">
        <button
          type="button"
          class="btn btn-sm join-item"
          aria-label="Zoom in"
          phx-click={JS.dispatch("graph:zoom", to: "##{@id}", detail: %{factor: 1.25})}
        >
          <span class="hero-plus size-4" />
        </button>
        <button
          type="button"
          class="btn btn-sm join-item"
          aria-label="Zoom out"
          phx-click={JS.dispatch("graph:zoom", to: "##{@id}", detail: %{factor: 0.8})}
        >
          <span class="hero-minus size-4" />
        </button>
        <button
          type="button"
          class="btn btn-sm join-item"
          aria-label="Fit to view"
          phx-click={JS.dispatch("graph:fit", to: "##{@id}")}
        >
          <span class="hero-arrows-pointing-in size-4" />
        </button>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".GraphViewport">
      // Pan, zoom and fit for a graph. The transform goes on the viewport element through
      // this.js(), so LiveView keeps it when it patches the graph.
      export default {
        mounted() {
          this.viewport = this.el.querySelector("[data-graph-viewport]")
          this.view = {x: 0, y: 0, scale: 1}
          this.moved = false
          this.fit()

          this.el.addEventListener("wheel", (e) => {
            e.preventDefault()
            const box = this.el.getBoundingClientRect()
            this.zoomAt(e.clientX - box.left, e.clientY - box.top, Math.exp(-e.deltaY * 0.002))
          }, {passive: false})

          this.el.addEventListener("pointerdown", (e) => {
            if (e.button !== 0 || e.target.closest("[data-graph-node], [data-graph-controls]")) return
            this.drag = {x: e.clientX - this.view.x, y: e.clientY - this.view.y}
            this.el.setPointerCapture(e.pointerId)
          })
          this.el.addEventListener("pointermove", (e) => {
            if (!this.drag) return
            this.moved = true
            this.apply({...this.view, x: e.clientX - this.drag.x, y: e.clientY - this.drag.y})
          })
          this.el.addEventListener("pointerup", () => { this.drag = null })

          this.el.addEventListener("graph:fit", () => { this.moved = false; this.fit() })
          this.el.addEventListener("graph:zoom", (e) => {
            this.zoomAt(this.el.clientWidth / 2, this.el.clientHeight / 2, e.detail.factor)
          })

          this.resize = new ResizeObserver(() => this.moved || this.fit())
          this.resize.observe(this.el)
        },
        updated() {
          this.moved ? this.apply(this.view) : this.fit()
        },
        destroyed() {
          this.resize?.disconnect()
        },
        fit() {
          const width = Number(this.el.dataset.width)
          const height = Number(this.el.dataset.height)
          if (!width || !height) return
          const scale = Math.min(this.el.clientWidth / width, this.el.clientHeight / height, 1)
          this.apply({
            scale,
            x: (this.el.clientWidth - width * scale) / 2,
            y: (this.el.clientHeight - height * scale) / 2,
          })
        },
        zoomAt(px, py, factor) {
          const scale = Math.min(Math.max(this.view.scale * factor, 0.2), 2)
          const k = scale / this.view.scale
          this.moved = true
          this.apply({scale, x: px - (px - this.view.x) * k, y: py - (py - this.view.y) * k})
        },
        apply(view) {
          this.view = view
          this.js().setAttribute(
            this.viewport,
            "style",
            `transform: translate(${view.x}px, ${view.y}px) scale(${view.scale})`
          )
        },
      }
    </script>
    """
  end
end
