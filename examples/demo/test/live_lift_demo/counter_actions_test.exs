defmodule LiveLiftDemo.CounterActionsTest do
  use ExUnit.Case, async: true

  alias LiveLiftDemo.CounterActions

  test "client actions have the same behavior in Elixir" do
    assert CounterActions.advance(%{count: 10, step: 2}) == %{count: 12, step: 2}
    assert CounterActions.retreat(%{count: 10, step: 2}) == %{count: 8, step: 2}
  end
end
