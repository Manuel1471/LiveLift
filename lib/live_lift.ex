defmodule LiveLift do
  @moduledoc """
  Small, opt-in client-side islands inside Phoenix LiveView.

  The first prototype is `LiveLift.Counter`. Server data remains owned by LiveView;
  the counter's value is temporary browser state. The JavaScript hook must be
  registered in the application's `LiveSocket`.
  """
end
