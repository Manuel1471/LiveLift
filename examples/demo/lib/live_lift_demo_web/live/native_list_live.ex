defmodule LiveLiftDemoWeb.NativeListLive do
  use LiveLiftDemoWeb, :live_view

  def mount(params, _session, socket) do
    count =
      case Integer.parse(Map.get(params, "rows", "2")) do
        {value, ""} when value in 1..1_000 -> value
        _ -> 2
      end

    items =
      Enum.map(1..count, fn index ->
        label =
          case index do
            1 -> "One"
            2 -> "Two"
            _ -> "Row #{index}"
          end

        %{id: "row-#{index}", label: label}
      end)

    {:ok,
     assign(socket,
       items: items,
       next_id: count + 1
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
