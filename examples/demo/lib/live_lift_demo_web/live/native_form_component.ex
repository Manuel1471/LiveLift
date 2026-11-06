defmodule LiveLiftDemoWeb.NativeFormComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section aria-label="Native LiveComponent form">
      <label>Draft <input name="value" phx-change="draft" phx-target={@myself} /></label>
      <output aria-live="polite">{@draft}</output>
      <form phx-submit="save" phx-target={@myself}>
        <label>Note <input name="note" /></label>
        <button type="submit">Save note</button>
      </form>
      <p>Saved: {@saved}</p>
    </section>
    """
  end

  @client true
  def handle_event("draft", params, socket) do
    {:noreply, assign(socket, :draft, params["value"])}
  end

  @client true
  def handle_event("save", params, socket) do
    {:noreply, assign(socket, :saved, params["note"])}
  end
end
