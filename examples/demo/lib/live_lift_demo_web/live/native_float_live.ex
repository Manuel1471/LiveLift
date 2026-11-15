defmodule LiveLiftDemoWeb.NativeFloatLive do
  use LiveLiftDemoWeb, :live_view

  def mount(_params, _session, socket), do: {:ok, assign(socket, :value, -0.0)}

  def render(assigns) do
    ~H"""
    <main>
      <h1>Native float parity</h1>
      <.live_component module={LiveLiftDemoWeb.NativeFloatComponent} id="native-float" value={@value} />
    </main>
    """
  end
end
