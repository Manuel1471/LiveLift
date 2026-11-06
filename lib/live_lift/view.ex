defmodule LiveLift.View do
  @moduledoc """
  Mounts a user-defined LiveLift client view inside a Phoenix LiveView.

  The supplied module owns the template and actions. This component only
  creates the DOM ownership boundary and renders the initial HTML.
  """

  use Phoenix.Component

  attr(:id, :string, required: true)
  attr(:module, :atom, required: true)
  attr(:state, :map, required: true)

  def island(assigns) do
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
