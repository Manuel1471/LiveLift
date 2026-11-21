defmodule LiveLiftDemoWeb.NativeCounterServerComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <section aria-label="Native LiveComponent counter">
      <button type="button" phx-click="inc" phx-target={@myself}>Add one</button>
      <button type="button" phx-click="reset" phx-target={@myself}>Reset on server</button>
      <button type="button" phx-click="save" phx-target={@myself}>Save on server</button>
      <output aria-live="polite">{@count}</output>
      <button type="button" phx-click="label" phx-value-label="ready" phx-target={@myself}>Set label</button>
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
    </section>
    """
  end

  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, :count, 0)}
  end

  def handle_event("save", _params, socket) do
    {:noreply, assign(socket, :label, "Saved #{socket.assigns.count}")}
  end

  def handle_event("label", params, socket) do
    {:noreply, assign(socket, :label, params["label"])}
  end
end
