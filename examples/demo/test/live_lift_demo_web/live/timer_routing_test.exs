defmodule LiveLiftDemoWeb.TimerRoutingTest do
  use LiveLiftDemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defmodule Component do
    use Phoenix.LiveComponent

    def mount(socket), do: {:ok, Phoenix.Component.assign(socket, :result, "waiting")}

    def render(assigns) do
      ~H"""
      <section>
        <button id="process-timer" phx-click="process" phx-target={@myself}>Process timer</button>
        <button id="component-timer" phx-click="component" phx-target={@myself}>Component timer</button>
        <output>{@result}</output>
      </section>
      """
    end

    def handle_event("process", _, socket) do
      Process.send_after(self(), {:probe, socket.assigns.id}, 0)
      {:noreply, socket}
    end

    def handle_event("component", _, socket) do
      Phoenix.LiveView.send_update_after(socket.assigns.myself, [result: "component update"], 0)
      {:noreply, socket}
    end

    def handle_info({:probe, _id}, socket),
      do: {:noreply, Phoenix.Component.assign(socket, :result, "component info")}
  end

  defmodule Parent do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <.live_component module={LiveLiftDemoWeb.TimerRoutingTest.Component} id="probe" />
      """
    end

    def handle_info({:probe, id}, socket) do
      send_update(LiveLiftDemoWeb.TimerRoutingTest.Component, id: id, result: "parent info")
      {:noreply, socket}
    end
  end

  test "process messages go to the parent while send_update_after targets the component", %{
    conn: conn
  } do
    {:ok, view, html} = live_isolated(conn, Parent)
    assert html =~ "waiting"

    view |> element("#process-timer") |> render_click()
    wait_for_output(view, "parent info")

    view |> element("#component-timer") |> render_click()
    wait_for_output(view, "component update")
  end

  defp wait_for_output(view, expected, remaining \\ 50) do
    html = render(view)

    if html =~ "<output>#{expected}</output>" do
      :ok
    else
      assert remaining > 0, "expected timer output #{inspect(expected)}, got #{html}"
      Process.sleep(10)
      wait_for_output(view, expected, remaining - 1)
    end
  end
end
