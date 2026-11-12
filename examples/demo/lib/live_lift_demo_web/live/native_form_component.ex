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
      <form phx-change="validate" phx-submit="save" phx-target={@myself}>
        <label>Note <input name="profile[note]" /></label>
        <button type="submit">Save note</button>
      </form>
      <.validation_error invalid={@invalid} />
      <p>Saved: {@saved}</p>
    </section>
    """
  end

  attr :invalid, :boolean, required: true

  defp validation_error(assigns) do
    ~H"""
    <p :if={@invalid} id="note-error" role="alert">Note must have at least 3 characters.</p>
    """
  end

  @client true
  def handle_event("draft", %{"value" => value}, socket) do
    {:noreply, socket |> assign(:draft, value)}
  end

  @client true
  def handle_event("validate", params, socket) do
    {:noreply,
     assign(
       socket,
       :invalid,
       String.length(String.trim(params["profile"]["note"])) < 3
     )}
  end

  @client true
  def handle_event("save", params, socket) do
    {:noreply,
     socket
     |> assign(:invalid, String.length(String.trim(params["profile"]["note"])) < 3)
     |> assign(
       :saved,
       if(String.length(String.trim(params["profile"]["note"])) < 3,
         do: socket.assigns.saved,
         else: params["profile"]["note"]
       )
     )
     |> assign(
       :active,
       if(String.length(String.trim(params["profile"]["note"])) < 3,
         do: socket.assigns.active,
         else: true
       )
     )}
  end
end
