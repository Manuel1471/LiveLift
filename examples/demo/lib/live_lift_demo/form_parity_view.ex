defmodule LiveLiftDemo.FormParityView do
  use Phoenix.LiveComponent
  use LiveLift

  def mount(socket) do
    {:ok, assign(socket, enabled: true, first: true, second: false, note: "A & <B>")}
  end

  def render(assigns) do
    ~H"""
    <section title="Forms &amp; entities">
      <form id="parity-choice" phx-change="choose" phx-target={@myself}>
        <label>Enabled <input type="checkbox" name="enabled" value="yes" checked={@enabled} /></label>
        <select name="choice" aria-label="Choice">
          <option value="a" selected={@first}>A</option>
          <option value="b" selected={@second}>B</option>
        </select>
      </form>
      <textarea name="value" aria-label="Note" phx-change="edit" phx-target={@myself}>{@note}</textarea>
      <output>{@note}</output>
      <button type="button" phx-click="reset" phx-target={@myself}>Reset form</button>
    </section>
    """
  end

  def handle_event("choose", %{"choice" => choice} = params, socket) when choice in ["a", "b"] do
    {:noreply,
     assign(socket,
       enabled: params["enabled"] == "yes",
       first: choice == "a",
       second: choice == "b"
     )}
  end

  @client true
  def handle_event("edit", %{"value" => value}, socket) do
    {:noreply, assign(socket, :note, value)}
  end

  @client true
  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> assign(:enabled, true)
     |> assign(:first, true)
     |> assign(:second, false)
     |> assign(:note, "A & <B>")}
  end
end
