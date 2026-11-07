defmodule LiveLiftDemoWeb.NativeListLive do
  use LiveLiftDemoWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       items: [%{id: "row-1", label: "One"}, %{id: "row-2", label: "Two"}],
       next_id: 3
     )}
  end

  def render(assigns) do
    ~H"""
    <main>
      <h1>Native keyed list</h1>
      <.live_component
        module={LiveLiftDemoWeb.NativeListComponent}
        id="native-list"
        items={@items}
        next_id={@next_id}
      />
    </main>
    """
  end
end
