Mix.install([
  {:ecto, "3.14.2"},
  {:phoenix_live_view, "1.2.13"},
  {:live_lift, path: Path.expand("..", __DIR__)}
])

defmodule ChangesetParityComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns), do: ~H"<output><span :if={@valid}>Valid</span>{@name}</output>"

  @client true
  def handle_event("validate", params, socket) do
    {:noreply,
     socket
     |> assign(:valid, validity(socket.assigns.data, params["profile"]))
     |> assign(
       :name,
       Ecto.Changeset.get_field(changeset(socket.assigns.data, params["profile"]), :name)
     )}
  end

  defp validity(data, params), do: changeset(data, params).valid?

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

inputs = [
  {"name", [:absent, "", " ", "é", "e\u0301", "é🙂", "👨‍👩‍👧‍👦a", "long name", "\u0085", "\uFEFF"]},
  {"code", [:absent, "", "OK", "OK\n", "bad", "ÉX", "A", "AB "]},
  {"zone",
   [:absent, "", "lab-1", "lab-1\n", "lab-1\r", "lab-1\r\n", "lab-1\u2028", "-1", "lab-x"]}
]

[{_, names}, {_, codes}, {_, zones}] = inputs

cases =
  for data <- [%{name: nil, code: nil, zone: nil}, %{name: "saved", code: "OK", zone: "lab-1"}],
      name <- names,
      code <- codes,
      zone <- zones do
    params =
      inputs
      |> Enum.map(&elem(&1, 0))
      |> Enum.zip([name, code, zone])
      |> Enum.reject(fn {_, value} -> value == :absent end)
      |> Map.new()

    params = %{"profile" => Map.put(params, "_unused_name", "")}
    state = %{data: data, name: "", valid: false}
    socket = struct!(Phoenix.LiveView.Socket, assigns: Map.put(state, :__changed__, %{}))

    {:reply, %{state: expected}, _} =
      ChangesetParityComponent.handle_event("validate", params, socket)

    %{state: state, params: params, expected: expected}
  end

source = LiveLift.Client.Compiler.compile_module(ChangesetParityComponent)
cases_json = Jason.encode!(cases)

javascript = """
#{source}
const cases = #{cases_json};
const compare = (actual, expected) =>
  actual.valid === expected.valid && actual.name === expected.name;
for (const {state, params, expected} of cases) {
  const actual = actions.validate(state, {params});
  if (!compare(actual, expected)) {
    throw new Error(JSON.stringify({state, params, expected, actual}));
  }
}
console.log(`Compared ${cases.length} changeset cases in Ecto and Node`);
"""

file = Path.join(System.tmp_dir!(), "live-lift-ecto-#{System.unique_integer([:positive])}.mjs")

try do
  File.write!(file, javascript)

  case System.cmd("node", [file], stderr_to_stdout: true) do
    {output, 0} -> IO.write(output)
    {output, status} -> raise "Node parity failed (#{status}): #{output}"
  end
after
  File.rm(file)
end
