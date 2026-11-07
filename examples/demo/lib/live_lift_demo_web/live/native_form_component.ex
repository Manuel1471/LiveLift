defmodule LiveLiftDemoWeb.NativeFormComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section
      class={["native-form", @active && "has-saved", @draft]}
      title={@saved}
      aria-label="Native LiveComponent form"
    >
      <label>Draft <input name="value" value={@draft} phx-change="draft" phx-target={@myself} /></label>
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
  def handle_event("draft", %{"value" => value}, socket) do
    {:noreply, socket |> assign(:draft, value)}
  end

  @client true
  def handle_event("save", params, socket) do
    {:noreply, socket |> assign(:saved, params["note"]) |> assign(:active, true)}
  end
end
