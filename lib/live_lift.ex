defmodule LiveLift do
  @moduledoc """
  Small, opt-in client-side islands inside Phoenix LiveView.

  `LiveLift.Client` defines restricted Elixir actions that compile to JavaScript.
  The first example is `LiveLift.Counter`. Server data remains owned by LiveView;
  the counter's value is temporary browser state. Register its JavaScript hook
  in the application's `LiveSocket`.
  """
end
