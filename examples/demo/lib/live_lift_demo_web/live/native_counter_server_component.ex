defmodule LiveLiftDemoWeb.NativeCounterServerComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <section aria-label="Native LiveComponent counter">
      <button type="button" phx-click="inc" phx-target={@myself}>Add one</button>
      <button type="button" phx-click="reset" phx-target={@myself}>Reset on server</button>
      <output aria-live="polite">{@count}</output>
      <button type="button" phx-click="label" phx-value-label="ready" phx-target={@myself}>Set label</button>
      <span>{@label}</span>
    </section>
    """
  end

  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, :count, 0)}
  end

  def handle_event("label", params, socket) do
    {:noreply, assign(socket, :label, params["label"])}
  end
end
