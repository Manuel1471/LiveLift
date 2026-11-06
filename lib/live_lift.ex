defmodule LiveLift do
  @moduledoc """
  Small, opt-in client-side islands inside Phoenix LiveView.

  `LiveLift.Client` defines restricted Elixir actions that compile to JavaScript.
  Applications provide their own HEEx and register LiveLift's generic hook in
  their `LiveSocket`. Server data remains owned by LiveView; each island's state
  is temporary browser data.
  """
end
