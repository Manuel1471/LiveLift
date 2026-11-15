defmodule LiveLiftDemoWeb.NativeFloatComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section aria-label="Native float parity">
      <output title={@value}>{@value}</output>
      <button phx-click="add_half" phx-target={@myself}>Add half</button>
    </section>
    """
  end

  @client true
  def handle_event("add_half", _params, socket) do
    {:noreply, update(socket, :value, &(&1 + 0.5))}
  end
end
