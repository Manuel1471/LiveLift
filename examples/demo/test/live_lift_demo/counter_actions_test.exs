defmodule LiveLiftDemo.CounterActionsTest do
  use ExUnit.Case, async: true

  alias LiveLiftDemo.CounterActions

  test "client actions have the same behavior in Elixir" do
    assert CounterActions.increment(10) == 11
    assert CounterActions.decrement(10) == 9
  end
end
