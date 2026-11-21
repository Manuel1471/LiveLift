defmodule LiveLiftDemoWeb.NativeCounterComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section aria-label="Native LiveComponent counter">
      <button type="button" phx-click="inc" phx-target={@myself}>Add one</button>
      <button type="button" phx-click="reset" phx-target={@myself}>Reset on server</button>
      <button type="button" phx-click="save" phx-target={@myself}>Save on server</button>
      <output aria-live="polite">{@count}</output>
      <button type="button" phx-click="label" phx-value-label="ready" phx-target={@myself}>Set label</button>
      <button type="button" phx-click="schedule" phx-target={@myself}>Schedule label on server</button>
      <button type="button" phx-click="preview_timer" phx-target={@myself}>Schedule label locally</button>
      <span>{@label}</span>
      <button
        type="button"
        id="open-native-preview"
        phx-click={Phoenix.LiveView.JS.dispatch("workspace:preview", bubbles: false)}
      >
        Open local preview
      </button>
      <button
        type="button"
        id="class-add"
        class={["class-sample", @label]}
        phx-click={Phoenix.LiveView.JS.add_class("accent")}
      >
        Add accent
      </button>
      <div phx-click={Phoenix.LiveView.JS.remove_class("initial", to: {:inner, ".class-sample"})}>
        <button type="button">Remove initial style</button>
        <p id="class-remove" class={["class-sample", "initial", @label]}>{@label}</p>
      </div>
      <div phx-click={Phoenix.LiveView.JS.toggle_class("accent", to: {:inner, ".class-sample"})}>
        <button type="button">Toggle accent</button>
        <p id="class-toggle" class={["class-sample", @label]}>{@label}</p>
      </div>
      <div phx-click={Phoenix.LiveView.JS.focus(to: {:inner, "#js-focus-target"})}>
        <label>Command focus target <input id="js-focus-target" /></label>
        <button type="button">Focus target</button>
      </div>
      <div phx-click={Phoenix.LiveView.JS.focus_first()}>
        <label>First focusable field <input id="js-focus-first" /></label>
        <button type="button">Focus first field</button>
      </div>
    </section>
    """
  end

  @client true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, :count, 0)}
  end

  def handle_event("save", _params, socket) do
    {:noreply, assign(socket, :label, "Saved #{socket.assigns.count}")}
  end

  def handle_event("schedule", _params, socket) do
    Phoenix.LiveView.send_update_after(socket.assigns.myself, [label: "Timer fired"], 50)
    {:noreply, socket}
  end

  @client true
  def handle_event("preview_timer", _params, socket) do
    Phoenix.LiveView.send_update_after(socket.assigns.myself, [label: "Local timer fired"], 100)
    {:noreply, socket}
  end

  @client true
  def handle_event("label", params, socket) do
    {:noreply, assign(socket, :label, params["label"])}
  end
end
