defmodule LiveLiftDemoWeb.NativeListComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section aria-label="Native LiveComponent list">
      <button type="button" phx-click="add" phx-target={@myself}>Add row</button>
      <button type="button" phx-click="reverse" phx-target={@myself}>Reverse rows</button>
      <ul>
        <li :for={item <- @items} id={item.id}>
          <form phx-submit="edit" phx-target={@myself}>
            <input type="hidden" name="row_id" value={item.id} />
            <label>Label <input name="label" value={item.label} /></label>
            <button type="submit">Save row</button>
          </form>
          <button type="button" phx-click="remove" phx-value-id={item.id} phx-target={@myself}>Remove</button>
        </li>
      </ul>
    </section>
    """
  end

  @client true
  def handle_event("add", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :items,
       socket.assigns.items ++
         [%{id: "row-" <> Integer.to_string(socket.assigns.next_id), label: "New"}]
     )
     |> update(:next_id, &(&1 + 1))}
  end

  @client true
  def handle_event("reverse", _params, socket) do
    {:noreply, update(socket, :items, &Enum.reverse(&1))}
  end

  @client true
  def handle_event("edit", params, socket) do
    {:noreply,
     update(
       socket,
       :items,
       &Enum.map(&1, fn item ->
         if item.id == params["row_id"], do: %{item | label: params["label"]}, else: item
       end)
     )}
  end

  @client true
  def handle_event("remove", params, socket) do
    {:noreply, update(socket, :items, &Enum.reject(&1, fn item -> item.id == params["id"] end))}
  end
end
