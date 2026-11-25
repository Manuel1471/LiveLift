defmodule LiveLiftDemoWeb.NativeOptionalComponent do
  use Phoenix.LiveComponent
  use LiveLift

  @client true
  def handle_event("initialize", _params, socket) do
    {:noreply,
     socket
     |> assign_new(:draft, fn -> socket.assigns.prefix <> " draft" end)
     |> assign(ready: true, status: "Draft ready")}
  end
end
