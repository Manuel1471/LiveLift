defmodule ChangesetParityComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <form phx-change="validate" phx-submit="validate" phx-target={@myself}>
      <label>Name <input name="profile[name]" value={@raw} /></label>
      <label>Code <input name="profile[code]" value={@raw_code} /></label>
      <label>Zone <input name="profile[zone]" /></label>
      <input type="hidden" name="profile[static]" value="fixed" />
      <button type="submit">Validate</button>
    </form>
    <output :if={@valid}>{@name}</output>
    <output :if={@used} id="name-used">{@raw}</output>
    <p :for={error <- @code_errors} id={error.id} role="alert">{error.message}</p>
    <span :if={@quiet_errors}></span>
    """
  end

  @client true
  def handle_event("validate", params, socket) do
    {:noreply,
     socket
     |> assign(:valid, validity(socket.assigns.data, params["profile"]))
     |> assign(
       :name,
       Ecto.Changeset.get_field(changeset(socket.assigns.data, params["profile"]), :name)
     )
     |> assign(:raw, form(socket.assigns.data, params["profile"])[:name].value)
     |> assign(
       :raw_code,
       Phoenix.HTML.Form.input_value(form(socket.assigns.data, params["profile"]), :code)
     )
     |> assign(
       :used,
       Phoenix.Component.used_input?(form(socket.assigns.data, params["profile"])[:name])
     )
     |> assign(:code_errors, code_errors(socket.assigns.data, params["profile"]))
     |> assign(:quiet_errors, quiet_errors(socket.assigns.data, params["profile"]))}
  end

  defp validity(data, params), do: changeset(data, params).valid?

  defp form(data, params),
    do: Phoenix.Component.to_form(changeset(data, params), as: :profile, action: :validate)

  defp quiet_errors(data, params) do
    Phoenix.Component.to_form(changeset(data, params), as: :profile)[:name].errors
    |> Enum.map(fn {message, _opts} -> message end)
  end

  defp code_errors(data, params) do
    form(data, params)[:code].errors
    |> Enum.map(fn {message, opts} ->
      %{id: String.replace(message, " ", "-"), message: message, count: Keyword.get(opts, :count)}
    end)
  end

  defp changeset(data, params) do
    Ecto.Changeset.cast({data, %{name: :string, code: :string, zone: :string}}, params, [
      :name,
      :code,
      :zone
    ])
    |> Ecto.Changeset.validate_required([:name, :code, :zone], [])
    |> Ecto.Changeset.validate_length(:name, min: 2, max: 8)
    |> Ecto.Changeset.validate_length(:code, is: 2)
    |> Ecto.Changeset.validate_format(:code, ~r/\A[A-Z]{2}\z/)
    |> Ecto.Changeset.validate_format(:zone, ~r/^[a-z]+-[0-9]$/, [])
  end
end
