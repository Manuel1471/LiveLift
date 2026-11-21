defmodule LiveLiftDemoWeb.NativeCounterComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section aria-label="Native LiveComponent counter">
      <button type="button" phx-click="inc" phx-target={@myself}>Add one</button>
      <button type="button" phx-click="reset" phx-target={@myself}>Reset on server</button>
      <button type="button" phx-click="save" phx-target={@myself}>Save on server</button>
      <output aria-live="polite">{@count}</output>
      <button type="button" phx-click="label" phx-value-label="ready" phx-target={@myself}>Set label</button>
      <button type="button" phx-click="schedule" phx-target={@myself}>Schedule label on server</button>
      <button type="button" phx-click="preview_timer" phx-target={@myself}>Schedule label locally</button>
      <span>{@label}</span>
    </section>
    """
  end

  @client true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, :count, 0)}
  end

  def handle_event("save", _params, socket) do
    {:noreply, assign(socket, :label, "Saved #{socket.assigns.count}")}
  end

  def handle_event("schedule", _params, socket) do
    Phoenix.LiveView.send_update_after(socket.assigns.myself, [label: "Timer fired"], 50)
    {:noreply, socket}
  end

  @client true
  def handle_event("preview_timer", _params, socket) do
    Phoenix.LiveView.send_update_after(socket.assigns.myself, [label: "Local timer fired"], 100)
    {:noreply, socket}
  end

  @client true
  def handle_event("label", params, socket) do
    {:noreply, assign(socket, :label, params["label"])}
  end
end
