defmodule LiveLiftDemoWeb.CounterLiveTest do
  use LiveLiftDemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the local island and updates server state", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ ~s(id="local-counter")
    assert html =~ ~s(data-live-lift-initial="10")
    assert html =~ "Server count: 0"

    assert view |> element("#server-increment") |> render_click() =~ "Server count: 1"
  end
end
