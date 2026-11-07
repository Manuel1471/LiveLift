defmodule LiveLiftDemoWeb.CounterLiveTest do
  use LiveLiftDemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the local island and updates server state", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ ~s(id="local-counter")

    assert html =~
             ~s(data-live-lift-server-fields="[&quot;saved_score&quot;,&quot;server_total&quot;]")

    assert html =~ ~s(phx-hook="LiveLift")
    assert html =~ ~s(data-live-lift-action="advance")
    assert html =~ ~s(data-live-lift-bind-value="count")
    assert html =~ ~s(id="task-list")
    assert html =~ ~s(data-live-lift-key="1")
    assert html =~ ~s(id="server-count")
    assert html =~ "server events"

    assert view |> element("#server-increment") |> render_click() =~ ~s(id="server-count")
    assert view |> element("#server-count") |> render() =~ ">1</strong>"
    assert view |> element(".history-chart") |> render() =~ "current count 1"

    assert_push_event(view, "live_lift:patch", %{
      id: "local-counter",
      revision: 1,
      patch: %{server_total: 1}
    })

    assert view
           |> element("#local-counter")
           |> render_hook("save_score", %{
             "state" => %{"count" => 12, "step" => 2},
             "revision" => 1
           }) =~
             ~s(id="saved-score")

    assert view |> element("#saved-score") |> render() =~ ">12</output>"

    assert_push_event(view, "live_lift:patch", %{
      id: "local-counter",
      revision: 2,
      patch: %{saved_score: 12}
    })

    view
    |> element("#local-counter")
    |> render_hook("save_score", %{"state" => %{"count" => 999}, "revision" => 1})

    view
    |> element("#local-counter")
    |> render_hook("save_score", %{"state" => %{"count" => 1001}, "revision" => 2})

    view
    |> element("#local-counter")
    |> render_hook("save_score", %{"state" => "invalid", "revision" => 2})

    assert view |> element("#saved-score") |> render() =~ ">12</output>"
  end
end
