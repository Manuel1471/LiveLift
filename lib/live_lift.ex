defmodule LiveLift do
  @moduledoc """
  Small, opt-in client-side islands inside Phoenix LiveView.

  `LiveLift.Client` defines restricted Elixir views and actions that compile to
  JavaScript. `LiveLift.View.island/1` mounts one within a regular LiveView.
  Server data remains owned by LiveView; each island's state is temporary
  browser data.
  """

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :client, persist: false)
      Module.register_attribute(__MODULE__, :live_lift_marked_actions, accumulate: true)
      @on_definition {LiveLift.Component, :on_definition}
      @before_compile LiveLift.Component
    end
  end
end
