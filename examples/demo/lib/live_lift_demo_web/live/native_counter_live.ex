defmodule LiveLiftDemoWeb.NativeCounterLive do
  use LiveLiftDemoWeb, :live_view

  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0)}

  def render(assigns) do
    component =
      if assigns.live_action == :server,
        do: LiveLiftDemoWeb.NativeCounterServerComponent,
        else: LiveLiftDemoWeb.NativeCounterComponent

    assigns = assign(assigns, :component, component)

    ~H"""
    <main>
      <h1>Native component migration</h1>
      <.live_component
        module={@component}
        id="native-counter"
        count={@count}
      />
    </main>
    """
  end
end
