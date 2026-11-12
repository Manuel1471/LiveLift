defmodule LiveLiftDemoWeb.NativeOptionalLive do
  use LiveLiftDemoWeb, :live_view

  def mount(_params, _session, socket), do: {:ok, assign(socket, :ready, false)}

  def render(assigns) do
    ~H"""
    <main>
      <h1>Optional client state</h1>
      <.live_component
        module={LiveLiftDemoWeb.NativeOptionalComponent}
        id="native-optional"
        prefix="Fresh"
        ready={@ready}
      />
    </main>
    """
  end
end
