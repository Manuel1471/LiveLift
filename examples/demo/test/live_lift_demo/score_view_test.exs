defmodule LiveLiftDemo.ScoreViewTest do
  use ExUnit.Case, async: true

  alias LiveLiftDemo.ScoreView

  test "client actions have the same behavior in Elixir" do
    assert ScoreView.advance(%{count: 10, step: 2, tone: "regular"}) == %{
             count: 12,
             step: 2,
             tone: "milestone"
           }

    assert ScoreView.retreat(%{count: 10, step: 2, tone: "regular"}) == %{
             count: 8,
             step: 2,
             tone: "regular"
           }
  end
end
