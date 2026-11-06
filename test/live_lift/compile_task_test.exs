defmodule LiveLift.CompileTaskTest do
  use ExUnit.Case, async: false

  test "generates a view registry and copies the browser runtime" do
    directory =
      Path.join(System.tmp_dir!(), "live_lift_compile_#{System.unique_integer([:positive])}")

    output = Path.join(directory, "generated_views.js")

    on_exit(fn -> File.rm_rf!(directory) end)
    Mix.Tasks.LiveLift.Compile.run(["--output", output])

    assert File.read!(output) =~ "export const views = {"

    assert File.read!(Path.join(directory, "live_lift_runtime.js")) =~
             "export function createClientHook"
  end
end
