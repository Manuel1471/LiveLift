defmodule LiveLiftDemoWeb.NativeCounterLive do
  use LiveLiftDemoWeb, :live_view

  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0, label: "")}

  def render(assigns) do
    component =
      if assigns.live_action == :server,
        do: LiveLiftDemoWeb.NativeCounterServerComponent,
        else: LiveLiftDemoWeb.NativeCounterComponent

    assigns = assign(assigns, :component, component)

    ~H"""
    <main>
      <h1>Native component migration</h1>
      <nav aria-label="Counter examples">
        <.link navigate={~p"/native-counter"}>Optimistic counter</.link>
        <.link navigate={~p"/native-counter-server"}>Server counter</.link>
      </nav>
      <.live_component
        module={@component}
        id="native-counter"
        count={@count}
        label={@label}
      />
      <dialog id="native-preview" aria-labelledby="native-preview-title">
        <h2 id="native-preview-title">Local preview</h2>
        <p>Phoenix delivered this event in your browser.</p>
        <form method="dialog">
          <button type="submit">Close preview</button>
        </form>
      </dialog>
    </main>
    """
  end
end
