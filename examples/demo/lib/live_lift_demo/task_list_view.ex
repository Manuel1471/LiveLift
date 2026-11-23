defmodule LiveLiftDemo.TaskListView do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section class="task-panel" aria-label="Custom client list">
      <div class="panel-topline">
        <span class="eyebrow"><span class="status-dot"></span> YOUR COMPONENTS / CLIENT</span><span class="runtime-pill">Keyed DOM</span>
      </div>
      <div class="panel-heading">
        <div>
          <h2>Build your own UI</h2><p>
            This list and its item component are defined by the app in Elixir.
          </p>
        </div>
      </div>
      <div class="task-add">
        <input
          type="text"
          aria-label="New task"
          placeholder="Write a task..."
          name="value"
          value={@draft}
          phx-change="set_draft"
          phx-target={@myself}
        />
        <button type="button" phx-click="add" phx-target={@myself}>Add task</button>
      </div>
      <ul class="task-list">
        <li :for={item <- @items} :key={item.id} id={item.id}>
          <.task_item item={item} myself={@myself} />
        </li>
      </ul>
      <p :if={@empty} class="task-empty">Your list is empty. Add a task above.</p>
      <button type="button" class="task-reverse" phx-click="reverse" phx-target={@myself}>Reverse order ↔</button>
    </section>
    """
  end

  defp task_item(assigns) do
    ~H"""
    <div class="task-item">
      <span class="task-bullet" aria-hidden="true">•</span>
      <form id={@item.form_id} phx-change="edit" phx-submit="edit" phx-target={@myself}>
        <input type="hidden" name="row_id" value={@item.id} />
        <input type="text" name="value" aria-label="Task name" value={@item.name} />
      </form>
      <button
        type="button"
        class="task-remove"
        phx-click="remove"
        phx-value-id={@item.id}
        phx-target={@myself}
        aria-label="Remove task"
      >×</button>
    </div>
    """
  end

  @client :local
  def handle_event("set_draft", %{"value" => value}, socket) do
    {:noreply, assign(socket, :draft, value)}
  end

  @client :local
  def handle_event("add", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :items,
       add_item(socket.assigns.items, socket.assigns.next_id, socket.assigns.draft)
     )
     |> assign(
       :next_id,
       if(socket.assigns.draft == "",
         do: socket.assigns.next_id,
         else: socket.assigns.next_id + 1
       )
     )
     |> assign(:empty, if(socket.assigns.draft == "", do: socket.assigns.empty, else: false))
     |> assign(:draft, "")}
  end

  @client :local
  def handle_event("remove", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:items, without_item(socket.assigns.items, id))
     |> assign(:empty, without_item(socket.assigns.items, id) == [])}
  end

  @client :local
  def handle_event("edit", %{"row_id" => id, "value" => value}, socket) do
    {:noreply,
     update(
       socket,
       :items,
       &Enum.map(&1, fn item ->
         if item.id == id, do: %{item | name: value}, else: item
       end)
     )}
  end

  @client :local
  def handle_event("reverse", _params, socket) do
    {:noreply, update(socket, :items, &Enum.reverse(&1))}
  end

  defp add_item(items, next_id, draft) do
    if draft == "",
      do: items,
      else:
        items ++
          [
            %{
              id: Integer.to_string(next_id),
              name: draft,
              form_id: "edit-task-" <> Integer.to_string(next_id)
            }
          ]
  end

  defp without_item(items, id), do: Enum.reject(items, fn item -> item.id == id end)
end
