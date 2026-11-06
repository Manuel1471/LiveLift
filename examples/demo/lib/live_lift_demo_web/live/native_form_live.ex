defmodule LiveLiftDemoWeb.NativeFormLive do
  use LiveLiftDemoWeb, :live_view

  def mount(_params, _session, socket), do: {:ok, assign(socket, draft: "", saved: "")}

  def render(assigns) do
    ~H"""
    <main>
      <h1>Native component form</h1>
      <.live_component
        module={LiveLiftDemoWeb.NativeFormComponent}
        id="native-form"
        draft={@draft}
        saved={@saved}
      />
    </main>
    """
  end
end
