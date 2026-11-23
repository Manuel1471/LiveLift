defmodule LiveLiftDemoWeb.CounterLiveTest do
  use LiveLiftDemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the native islands and handles explicit saves on the server", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ ~s(id="local-counter")
    assert html =~ ~s(phx-hook="LiveLift")
    assert html =~ ~s(phx-click="advance")
    assert html =~ ~s(phx-value-count="10")
    assert html =~ ~s(id="task-list")
    assert html =~ ~s(<li id="1")
    assert html =~ ~s(id="server-count")
    assert html =~ "server events"

    assert view |> element("#server-increment") |> render_click() =~ ~s(id="server-count")
    assert view |> element("#server-count") |> render() =~ ">1</strong>"
    assert view |> element(".history-chart") |> render() =~ "current count 1"
    assert view |> element("#local-counter") |> render() =~ "&quot;server_total&quot;:1"

    save = element(view, ~s(#local-counter [phx-click="save_score"]))
    render_click(save, %{"count" => "12", "revision" => "1"})

    assert view |> element("#saved-score") |> render() =~ ">12</output>"
    assert view |> element("#local-counter") |> render() =~ "&quot;saved_score&quot;:12"

    render_click(save, %{"count" => "999", "revision" => "1"})
    render_click(save, %{"count" => "1001", "revision" => "2"})
    render_click(save, %{"count" => "invalid", "revision" => "2"})

    assert view |> element("#saved-score") |> render() =~ ">12</output>"
  end
end
