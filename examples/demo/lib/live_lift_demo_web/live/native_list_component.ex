defmodule LiveLiftDemoWeb.NativeListComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section aria-label="Native LiveComponent list">
      <button type="button" phx-click="add" phx-target={@myself}>Add row</button>
      <button type="button" phx-click="reset_last" phx-target={@myself}>Reset last row</button>
      <button type="button" phx-click="remove_last" phx-target={@myself}>Remove last row</button>
      <button type="button" phx-click="reverse" phx-target={@myself}>Reverse rows</button>
      <button type="button" phx-click="sort_labels" phx-target={@myself}>Sort labels</button>
      <button type="button" phx-click="find_new" phx-target={@myself}>Find new row</button>
      <output aria-label="First new row">{@first_match}</output>
      <button type="button" phx-click="combine_labels" phx-target={@myself}>Combine labels</button>
      <button type="button" phx-click="join_labels" phx-target={@myself}>Join labels</button>
      <button type="button" phx-click="expand_labels" phx-target={@myself}>Expand labels</button>
      <button type="button" phx-click="number_labels" phx-target={@myself}>Number labels</button>
      <button type="button" phx-click="lower_labels" phx-target={@myself}>Lower labels</button>
      <button type="button" phx-click="split_labels" phx-target={@myself}>Split labels</button>
      <button type="button" phx-click="replace_labels" phx-target={@myself}>Replace first comma</button>
      <button type="button" phx-click="summarize_fields" phx-target={@myself}>Summarize fields</button>
      <output aria-label="Combined labels">{@combined_labels}</output>
      <button type="button" phx-click="count_new" phx-target={@myself}>Count new rows</button>
      <output aria-label="New row count">{@new_count}</output>
      <ul>
        <li :for={item <- @items} id={item.id} title={@first_match}>
          <form phx-change="edit" phx-submit="edit" phx-target={@myself}>
            <input type="hidden" name="row_id" value={item.id} />
            <label>Label <input name="label" value={item.label} /></label>
            <button type="submit">Save row</button>
          </form>
          <button type="button" phx-click="remove" phx-value-id={item.id} phx-target={@myself}>Remove</button>
          <.move_button row_id={item.id} myself={@myself} />
        </li>
      </ul>
    </section>
    """
  end

  attr :row_id, :string, required: true
  attr :myself, :any, required: true

  defp move_button(assigns) do
    ~H"""
    <button type="button" phx-click="move_to_top" phx-value-id={@row_id} phx-target={@myself}>Move to top</button>
    """
  end

  @client true
  def handle_event("add", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :items,
       List.insert_at(socket.assigns.items, -1, %{
         id: "row-" <> Integer.to_string(socket.assigns.next_id),
         label: "New"
       })
     )
     |> update(:next_id, &(&1 + 1))}
  end

  @client true
  def handle_event("reset_last", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :items,
       List.replace_at(socket.assigns.items, -1, %{
         id: "row-" <> Integer.to_string(socket.assigns.next_id),
         label: "Reset"
       })
     )
     |> update(:next_id, &(&1 + 1))}
  end

  @client true
  def handle_event("remove_last", _params, socket) do
    {:noreply, update(socket, :items, &List.delete_at(&1, -1))}
  end

  @client true
  def handle_event("reverse", _params, socket) do
    {:noreply, update(socket, :items, &Enum.reverse(&1))}
  end

  @client true
  def handle_event("sort_labels", _params, socket) do
    {:noreply, update(socket, :items, &Enum.sort_by(&1, fn item -> item.label end))}
  end

  @client true
  def handle_event("find_new", _params, socket) do
    {:noreply,
     assign(
       socket,
       :first_match,
       Enum.find(socket.assigns.items, %{id: "none", label: "None"}, fn item ->
         item.label == "New"
       end).label
     )}
  end

  @client true
  def handle_event("combine_labels", _params, socket) do
    {:noreply,
     assign(
       socket,
       :combined_labels,
       Enum.reduce(socket.assigns.items, "", fn item, labels -> labels <> item.label end)
     )}
  end

  @client true
  def handle_event("join_labels", _params, socket) do
    {:noreply,
     assign(
       socket,
       :combined_labels,
       socket.assigns.items |> Enum.map(fn item -> item.label end) |> Enum.join(" · ")
     )}
  end

  @client true
  def handle_event("expand_labels", _params, socket) do
    {:noreply,
     assign(
       socket,
       :combined_labels,
       socket.assigns.items
       |> Enum.flat_map(fn item ->
         if item.label == "New", do: [item.label, "!"], else: [item.label]
       end)
       |> Enum.join(" · ")
     )}
  end

  @client true
  def handle_event("number_labels", _params, socket) do
    {:noreply,
     assign(
       socket,
       :combined_labels,
       socket.assigns.items
       |> Enum.with_index(fn item, index ->
         Integer.to_string(index + 1) <> ": " <> item.label
       end)
       |> Enum.join(" · ")
     )}
  end

  @client true
  def handle_event("lower_labels", _params, socket) do
    {:noreply,
     assign(
       socket,
       :combined_labels,
       socket.assigns.items
       |> Enum.map(fn item -> item.label end)
       |> Enum.join(" · ")
       |> String.downcase()
     )}
  end

  @client true
  def handle_event("split_labels", _params, socket) do
    {:noreply,
     assign(
       socket,
       :combined_labels,
       socket.assigns.items
       |> Enum.map(fn item -> item.label end)
       |> Enum.join(",")
       |> String.split(",", trim: true)
       |> Enum.join(" · ")
     )}
  end

  @client true
  def handle_event("replace_labels", _params, socket) do
    {:noreply,
     assign(
       socket,
       :combined_labels,
       socket.assigns.items
       |> Enum.map(fn item -> item.label end)
       |> Enum.join(",")
       |> String.replace(",", " · ", global: false)
     )}
  end

  @client true
  def handle_event("summarize_fields", _params, socket) do
    {:noreply,
     assign(
       socket,
       :combined_labels,
       (%{rows: socket.assigns.items, next_id: socket.assigns.next_id}
        |> Map.keys()
        |> Enum.map(&Atom.to_string/1)
        |> Enum.sort()
        |> Enum.join(" · ")) <>
         " (" <>
         Integer.to_string(
           Enum.count(Map.values(%{rows: socket.assigns.items, next_id: socket.assigns.next_id}))
         ) <>
         ")"
     )}
  end

  @client true
  def handle_event("count_new", _params, socket) do
    {:noreply,
     assign(
       socket,
       :new_count,
       Enum.count(socket.assigns.items, fn item -> item.label == "New" end)
     )}
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
    {:noreply,
     assign(
       socket,
       :items,
       List.delete(
         socket.assigns.items,
         Enum.find(socket.assigns.items, fn item -> item.id == params["id"] end)
       )
     )}
  end

  @client true
  def handle_event("move_to_top", params, socket) do
    {:noreply,
     update(
       socket,
       :items,
       &(Enum.filter(&1, fn item -> item.id == params["id"] end) ++
           Enum.reject(&1, fn item -> item.id == params["id"] end))
     )}
  end
end
