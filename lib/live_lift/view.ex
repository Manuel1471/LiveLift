defmodule LiveLift.View do
  @moduledoc """
  Mounts a user-defined LiveLift client view inside a Phoenix LiveView.

  The supplied module owns the template and actions. This component only
  creates the DOM ownership boundary and renders the initial HTML.
  """

  use Phoenix.Component

  @max_safe_integer 9_007_199_254_740_991

  attr(:id, :string, required: true)
  attr(:module, :atom, required: true)
  attr(:state, :map, required: true)

  def island(assigns) do
    unless Enum.all?(assigns.state, fn {key, value} ->
             is_atom(key) and is_integer(value) and abs(value) <= @max_safe_integer
           end) do
      raise ArgumentError, "LiveLift state must be a map of atom keys and safe integers"
    end

    template = assigns.module.__live_lift_client_template__()

    unless is_binary(template) do
      raise ArgumentError, "#{inspect(assigns.module)} has no client_template"
    end

    html = LiveLift.Template.render_server(template, assigns.state)
    assigns = assign(assigns, :html, html)

    ~H"""
    <div
      id={@id}
      phx-hook="LiveLift"
      phx-update="ignore"
      data-live-lift-module={inspect(@module)}
      data-live-lift-state={Jason.encode!(@state)}
    >
      {@html}
    </div>
    """
  end
end
