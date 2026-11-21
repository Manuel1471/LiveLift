defmodule ConsumerLiftWeb.CounterComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <section>
      <button id="inc" phx-click="inc" phx-target={@myself}>Add</button>
      <button id="save" phx-click="save" phx-target={@myself}>Save</button>
      <output id="count">{@count}</output>
      <span id="saved">{@saved}</span>
    </section>
    """
  end

  def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}

  def handle_event("preview", _params, socket) do
    Phoenix.LiveView.send_update_after(socket.assigns.myself, [saved: "Ready"], 50)
    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    {:noreply, assign(socket, :saved, "Saved #{socket.assigns.count}")}
  end
end
