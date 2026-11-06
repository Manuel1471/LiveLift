defmodule Mix.Tasks.LiveLift.Compile do
  use Mix.Task

  @shortdoc "Compiles app LiveLift.Client views to a JavaScript registry"

  @impl Mix.Task
  def run(args) do
    {opts, modules, invalid} = OptionParser.parse(args, strict: [output: :string])

    unless invalid == [] and modules == [] and is_binary(opts[:output]) do
      Mix.raise("usage: mix live_lift.compile --output assets/js/generated_views.js")
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
    File.mkdir_p!(Path.dirname(output))
    File.write!(output, LiveLift.Client.Compiler.compile_registry(view_modules))
    Mix.shell().info("Generated #{Path.relative_to_cwd(output)} (#{length(view_modules)} views)")
  end
end
