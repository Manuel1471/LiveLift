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
  attr(:server_fields, :list, default: [])
  attr(:server_revision, :integer, default: 0)

  def island(assigns) do
    LiveLift.State.validate!(assigns.state)
    fields = Enum.map(assigns.server_fields, &to_string/1)

    state_fields = Map.keys(assigns.state) |> Enum.map(&to_string/1)

    unless Enum.uniq(fields) == fields and Enum.all?(fields, &(&1 in state_fields)) do
      raise ArgumentError, "server_fields must be unique keys present in island state"
    end

    unless is_integer(assigns.server_revision) and assigns.server_revision >= 0 and
             assigns.server_revision <= 9_007_199_254_740_991 do
      raise ArgumentError, "server_revision must be a non-negative safe integer"
    end

    template = assigns.module.__live_lift_client_template__()

    unless is_list(template) do
      raise ArgumentError, "#{inspect(assigns.module)} has no client_template"
    end

    html = LiveLift.Template.render_server(template, assigns.state)
    assigns = assigns |> assign(:html, html) |> assign(:server_fields_json, Jason.encode!(fields))

    ~H"""
    <div
      id={@id}
      phx-hook="LiveLift"
      phx-update="ignore"
      data-live-lift-module={inspect(@module)}
      data-live-lift-state={Jason.encode!(@state)}
      data-live-lift-server-fields={@server_fields_json}
      data-live-lift-server-revision={@server_revision}
    >
      {@html}
    </div>
    """
  end
end
