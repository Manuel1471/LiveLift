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
      <label>Debounced draft
      <input name="value" value={@draft} phx-change="draft" phx-debounce="300" phx-target={@myself} /></label>
      <output aria-live="polite">{@draft}</output>
      <form
        id="native-note"
        phx-change="validate"
        phx-submit="save"
        phx-auto-recover="ignore"
        phx-target={@myself}
      >
        <.note_field>
          <input name="profile[note]" value={@note_value} data-live-lift-draft={@draft_scope} />
        </.note_field>
        <button type="submit">Save note</button>
        <button type="reset">Discard draft</button>
      </form>
      <.feedback title={@saved}><.validation_error invalid={@invalid} /></.feedback>
      <p>Saved: {@saved}</p>
    </section>
    """
  end

  slot :inner_block, required: true

  defp note_field(assigns) do
    ~H"""
    <label>Note {render_slot(@inner_block)}</label>
    """
  end

  attr :invalid, :boolean, required: true

  defp validation_error(assigns) do
    ~H"""
    <p :if={@invalid} id="note-error" role="alert">Note must have at least 3 characters.</p>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp feedback(assigns) do
    ~H"""
    <div class="form-feedback" title={@title}>{render_slot(@inner_block)}</div>
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
