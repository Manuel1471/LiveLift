defmodule LiveLiftDemoWeb.LocalActionsLive do
  use LiveLiftDemoWeb, :live_view
  use LiveLift

  def mount(_params, _session, socket) do
    {:ok, assign(socket, rows: initial_rows(), count: 0, saved_first: "None")}
  end

  def render(assigns) do
    ~H"""
    <main id="local-actions" class="mx-auto max-w-lg space-y-4 p-6">
      <h1 class="text-2xl font-bold">Local sorting with LiveView</h1>
      <p>Reverse the list in the browser, then select a row to save it on the server.</p>
      <ol class="list-decimal pl-6" aria-label="Preview order">
        <li :for={row <- @rows} :key={row.id} id={row.id}>
          <button type="button" phx-click="save_first" phx-value-id={row.id}>{row.label}</button>
        </li>
      </ol>
      <div class="flex gap-3">
        <button type="button" phx-click="reverse_preview">Reverse preview</button>
        <button type="button" phx-click="increase_count">Increase shared count</button>
      </div>
      <p>Shared count <output id="local-shared-count">{@count}</output></p>
      <p>Saved row <output id="local-saved-first">{@saved_first}</output></p>
    </main>
    """
  end

  @client :local
  def handle_event("reverse_preview", _params, socket) do
    {:noreply, update(socket, :rows, &Enum.reverse(&1))}
  end

  @client true
  def handle_event("increase_count", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("save_first", %{"id" => id}, socket) do
    case Enum.find(initial_rows(), &(&1.id == id)) do
      nil -> {:noreply, socket}
      row -> {:noreply, assign(socket, :saved_first, row.label)}
    end
  end

  defp initial_rows, do: [%{id: "one", label: "One"}, %{id: "two", label: "Two"}]
end
