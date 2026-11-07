defmodule LiveLiftDemoWeb.NativeListComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section aria-label="Native LiveComponent list">
      <button type="button" phx-click="reverse" phx-target={@myself}>Reverse rows</button>
      <ul>
        <li :for={item <- @items} id={item.id}>
          <label>{item.label}<input value={item.label} /></label>
        </li>
      </ul>
    </section>
    """
  end

  @client true
  def handle_event("reverse", _params, socket) do
    {:noreply, update(socket, :items, &Enum.reverse(&1))}
  end
end
