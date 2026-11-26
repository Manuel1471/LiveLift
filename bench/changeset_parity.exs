Mix.install([
  {:ecto, "3.14.3"},
  {:phoenix_ecto, "4.7.0"},
  {:phoenix_live_view, "1.2.15"},
  {:live_lift, path: Path.expand("..", __DIR__)}
])

Code.require_file("support/changeset_component.exs", __DIR__)

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

    profile = if name in ["é", ""], do: Map.put(params, "_unused_name", ""), else: params
    params = %{"profile" => Map.put(profile, "_unused_zone", "")}

    state = %{
      data: data,
      name: "",
      valid: false,
      used: false,
      raw: nil,
      raw_code: nil,
      code_errors: [],
      quiet_errors: []
    }

    socket = struct!(Phoenix.LiveView.Socket, assigns: Map.put(state, :__changed__, %{}))

    {:reply, %{state: expected}, _} =
      ChangesetParityComponent.handle_event("validate", params, socket)

    %{state: state, params: params, expected: expected}
  end

fixture =
  LiveLift.Client.Compiler.compile_module(ChangesetParityComponent) <>
    "\nexport const cases = #{Jason.encode!(cases)};\n"

javascript = """
#{fixture}
import assert from "node:assert/strict";
for (const {state, params, expected} of cases) {
  assert.deepEqual(actions.validate(state, {params}), expected, JSON.stringify({state, params}));
}
console.log(`Compared ${cases.length} changeset cases in Ecto and Node`);
"""

case System.argv() do
  ["--browser", output] ->
    File.write!(output, fixture)

  ["--registry", output] ->
    registry = LiveLift.Client.Compiler.compile_registry([ChangesetParityComponent])
    File.write!(output, registry <> "\nexport const cases = #{Jason.encode!(cases)};\n")

  [] ->
    file =
      Path.join(System.tmp_dir!(), "live-lift-ecto-#{System.unique_integer([:positive])}.mjs")

    try do
      File.write!(file, javascript)

      case System.cmd("node", [file], stderr_to_stdout: true) do
        {output, 0} -> IO.write(output)
        {output, status} -> raise "Node parity failed (#{status}): #{output}"
      end
    after
      File.rm(file)
    end
end
