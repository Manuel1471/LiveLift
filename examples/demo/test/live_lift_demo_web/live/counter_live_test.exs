defmodule LiveLiftDemoWeb.CounterLiveTest do
  use LiveLiftDemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the local island and updates server state", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ ~s(id="local-counter")
    assert html =~ ~s(phx-hook="LiveLift")
    assert html =~ ~s(data-live-lift-action="advance")
    assert html =~ "Server count: 0"

    assert view |> element("#server-increment") |> render_click() =~ "Server count: 1"

    assert view
           |> element("#local-counter")
           |> render_hook("save_score", %{"state" => %{"count" => 12, "step" => 2}}) =~
             "Saved score: 12"
  end
end
