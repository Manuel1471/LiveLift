defmodule LiveLiftDemo.ScoreViewTest do
  use ExUnit.Case, async: true

  alias LiveLiftDemo.ScoreView

  test "Elixir handlers advance, retreat, and reset the score" do
    assigns = %{
      __changed__: %{},
      count: 10,
      step: 2,
      tone: "regular",
      title: "Local score",
      milestone: false,
      saved_score: nil,
      server_total: 0,
      sync_revision: 0
    }

    socket = %Phoenix.LiveView.Socket{assigns: assigns}

    assert {:reply, %{state: %{count: 12, tone: "milestone", milestone: true}}, _} =
             ScoreView.handle_event("advance", %{}, socket)

    assert {:reply, %{state: %{count: 8, tone: "regular", milestone: false}}, _} =
             ScoreView.handle_event("retreat", %{}, socket)

    socket = Phoenix.Component.assign(socket, :count, 14)

    assert {:reply, %{state: %{count: 10, tone: "regular", milestone: false}}, _} =
             ScoreView.handle_event("reset", %{}, socket)
  end
end
