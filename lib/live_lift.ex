defmodule LiveLift do
  @moduledoc """
  Small, opt-in client-side islands inside Phoenix LiveView.

  `LiveLift.Client` defines restricted Elixir views and actions that compile to
  JavaScript. `LiveLift.View.island/1` mounts one within a regular LiveView.
  Server data remains owned by LiveView; each island's state is temporary
  browser data.
  """
end
