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

    assert File.read!(Path.join(directory, "generated_views.d.ts")) =~
             ~s(from "./live_lift_runtime.js")

    assert File.read!(Path.join(directory, "live_lift_runtime.d.ts")) =~
             "export declare function createClientHook"
  end

  test "copied registries reject an incompatible runtime before loading views" do
    directory =
      Path.join(System.tmp_dir!(), "live_lift_compat_#{System.unique_integer([:positive])}")

    output = Path.join(directory, "app/generated_views.mjs")
    runtime = Path.join(directory, "runtime/client.mjs")

    on_exit(fn -> File.rm_rf!(directory) end)

    Mix.Tasks.LiveLift.Compile.run(["--output", output, "--runtime-output", runtime])

    assert File.read!(output) =~ ~s(from "../runtime/client.mjs")
    assert File.read!(Path.rootname(output) <> ".d.mts") =~ ~s(from "../runtime/client.mjs")
    assert File.exists?(Path.rootname(runtime) <> ".d.mts")

    command = ["--input-type=module", "-e", "await import(process.argv[1])", output]
    assert {_, 0} = System.cmd("node", command, stderr_to_stdout: true)

    source = File.read!(runtime)
    File.write!(runtime, String.replace(source, "__liveLiftRuntime_", "__differentRuntime_"))

    assert {error, 1} = System.cmd("node", command, stderr_to_stdout: true)
    assert error =~ "does not provide an export named '__liveLiftRuntime_"
  end

  test "npm runtime is exclusive with writing a copied runtime" do
    assert_raise Mix.Error, ~r/--runtime-output.*--npm-runtime/, fn ->
      Mix.Tasks.LiveLift.Compile.run([
        "--output",
        "unused.js",
        "--runtime-output",
        "unused_runtime.js",
        "--npm-runtime"
      ])
    end
  end
end
