defmodule LiveLiftDemoWeb.NativeFormLive do
  use LiveLiftDemoWeb, :live_view

  def mount(params, _session, socket) do
    scope = if params["record"] == "other", do: "demo-other", else: "demo-note"

    note_value = if params["record"] == "bound", do: "Server note"

    {:ok,
     assign(socket,
       draft_scope: scope,
       note_value: note_value,
       draft: nil,
       saved: "",
       active: false,
       invalid: false
     )}
  end

  def render(assigns) do
    ~H"""
    <main>
      <h1>Native component form</h1>
      <.live_component
        module={LiveLiftDemoWeb.NativeFormComponent}
        id="native-form"
        draft={@draft}
        draft_scope={@draft_scope}
        note_value={@note_value}
        saved={@saved}
        active={@active}
        invalid={@invalid}
      />
    </main>
    """
  end
end
