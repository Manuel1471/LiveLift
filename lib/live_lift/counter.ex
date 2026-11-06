defmodule LiveLift.Counter do
  @moduledoc """
  A local counter for a LiveView template.

  This component demonstrates LiveLift's first state boundary: the initial value
  comes from the server, and later clicks update only the browser. Because the
  container uses `phx-update="ignore"`, subsequent server renders do not replace
  its children or reset the local count.

      <LiveLift.Counter.counter id="demo-counter" initial={10} />
  """

  use Phoenix.Component

  attr(:id, :string, required: true)
  attr(:initial, :integer, default: 0)

  def counter(assigns) do
    ~H"""
    <div id={@id} phx-hook="LiveLift.Counter" phx-update="ignore" data-live-lift-initial={@initial}>
      <button type="button" data-live-lift-action="decrement" aria-label="Decrement">−</button>
      <output data-live-lift-value aria-live="polite">{@initial}</output>
      <button type="button" data-live-lift-action="increment" aria-label="Increment">+</button>
    </div>
    """
  end
end
