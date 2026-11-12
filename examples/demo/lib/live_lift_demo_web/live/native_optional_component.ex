defmodule LiveLiftDemoWeb.NativeOptionalComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section aria-label="Optional native state">
      <button phx-click="initialize" phx-target={@myself}>Initialize draft</button>
      <p :if={@ready}>{@draft}</p>
    </section>
    """
  end

  @client true
  def handle_event("initialize", _params, socket) do
    {:noreply,
     socket
     |> assign_new(:draft, fn -> socket.assigns.prefix <> " draft" end)
     |> assign(:ready, true)}
  end
end
