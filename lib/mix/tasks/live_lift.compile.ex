defmodule Mix.Tasks.LiveLift.Compile do
  use Mix.Task

  @shortdoc "Compiles app LiveLift.Client views to a JavaScript registry"

  @impl Mix.Task
  def run(args) do
    {opts, modules, invalid} =
      OptionParser.parse(args, strict: [output: :string, runtime_output: :string])

    unless invalid == [] and modules == [] and is_binary(opts[:output]) do
      Mix.raise(
        "usage: mix live_lift.compile --output assets/js/generated_views.js [--runtime-output assets/js/live_lift_runtime.js]"
      )
    end

    Mix.Task.run("compile")

    app = Mix.Project.config()[:app]

    case Application.load(app) do
      :ok -> :ok
      {:error, {:already_loaded, ^app}} -> :ok
    end

    view_modules =
      app
      |> Application.spec(:modules)
      |> Enum.filter(fn module ->
        Code.ensure_loaded?(module) and
          function_exported?(module, :__live_lift_client_template__, 0) and
          is_binary(module.__live_lift_client_template__())
      end)

    output = Path.expand(opts[:output])

    runtime_output =
      Path.expand(
        opts[:runtime_output] || Path.join(Path.dirname(output), "live_lift_runtime.js")
      )

    if runtime_output == output do
      Mix.raise("registry and runtime outputs must use different paths")
    end

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, LiveLift.Client.Compiler.compile_registry(view_modules))
    File.mkdir_p!(Path.dirname(runtime_output))

    runtime_source = Path.expand("../../../assets/js/live_lift/client_hook.js", __DIR__)
    File.cp!(runtime_source, runtime_output)

    Mix.shell().info("Generated #{Path.relative_to_cwd(output)} (#{length(view_modules)} views)")
    Mix.shell().info("Copied #{Path.relative_to_cwd(runtime_output)}")
  end
end
