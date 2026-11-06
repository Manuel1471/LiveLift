defmodule LiveLift.CounterTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  test "renders an isolated counter with its initial value" do
    html = render_component(&LiveLift.Counter.counter/1, id: "counter-1", initial: 7)

    assert html =~ ~s(id="counter-1")
    assert html =~ ~s(phx-hook="LiveLift.Counter")
    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(data-live-lift-initial="7")
    assert html =~ ">7</output>"
  end
end
