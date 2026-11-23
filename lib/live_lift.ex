defmodule LiveLift do
  @moduledoc """
  Opt-in browser interactions for Phoenix LiveViews and LiveComponents.

  Add `use LiveLift` to a routed LiveView or stateful LiveComponent and put
  `@client true` before a supported `handle_event/3`. LiveLift compiles the handler and its
  existing `~H` template for immediate browser prediction. LiveView still runs
  the original handler on server-owned state and sends the authoritative result.

  Use `@client :local` for transient assigns such as a list's preview order.
  Once the hook mounts, this action runs without sending a LiveView event.

  The earlier `LiveLift.Client` and `LiveLift.View.island/1` API remains
  available for existing apps while they migrate.
  """

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :client, persist: false)
      Module.register_attribute(__MODULE__, :live_lift_marked_actions, accumulate: true)
      Module.register_attribute(__MODULE__, :live_lift_local_components, accumulate: true)
      Module.register_attribute(__MODULE__, :live_lift_local_helpers, accumulate: true)
      Module.register_attribute(__MODULE__, :live_lift_info_callbacks, accumulate: true)
      @on_definition {LiveLift.Component, :on_definition}
      @before_compile LiveLift.Component
    end
  end
end
