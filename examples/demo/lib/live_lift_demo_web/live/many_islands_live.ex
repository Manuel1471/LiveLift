defmodule LiveLiftDemoWeb.ManyIslandsLive do
  use LiveLiftDemoWeb, :live_view

  def mount(params, _session, socket) do
    count =
      case Integer.parse(Map.get(params, "count", "100")) do
        {value, ""} when value in 1..500 -> value
        _ -> 100
      end

    component =
      if Map.get(params, "mode") == "server",
        do: LiveLiftDemoWeb.NativeCounterServerComponent,
        else: LiveLiftDemoWeb.NativeCounterComponent

    {:ok, assign(socket, islands: Enum.to_list(1..count), component: component)}
  end

  def render(assigns) do
    ~H"""
    <main>
      <h1>Many LiveComponents</h1>
      <div id="many-islands">
        <div :for={index <- @islands} id={"island-wrap-#{index}"}>
          <.live_component
            module={@component}
            id={"island-#{index}"}
            count={0}
            label=""
          />
        </div>
      </div>
    </main>
    """
  end
end
