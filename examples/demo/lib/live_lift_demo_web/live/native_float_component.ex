defmodule LiveLiftDemoWeb.NativeFloatComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section aria-label="Native float parity">
      <output title={@value}>{@value}</output>
      <button phx-click="add_half" phx-target={@myself}>Add half</button>
      <button phx-click="minimum_one" phx-target={@myself}>Minimum one</button>
    </section>
    """
  end

  @client true
  def handle_event("add_half", _params, socket) do
    {:noreply, update(socket, :value, &(&1 + 0.5))}
  end

  @client true
  def handle_event("minimum_one", _params, socket) do
    {:noreply,
     assign(
       socket,
       :value,
       cond do
         socket.assigns.value < 1.0 -> 1.0
         true -> socket.assigns.value
       end
     )}
  end
end
