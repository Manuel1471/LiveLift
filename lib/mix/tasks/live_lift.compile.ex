defmodule Mix.Tasks.LiveLift.Compile do
  use Mix.Task

  @shortdoc "Compiles a LiveLift.Client module to a JavaScript actions file"

  @impl Mix.Task
  def run(args) do
    {opts, modules, invalid} = OptionParser.parse(args, strict: [output: :string])

    unless invalid == [] and length(modules) == 1 and is_binary(opts[:output]) do
      Mix.raise("usage: mix live_lift.compile MyApp.CounterActions --output assets/js/actions.js")
    end

    Mix.Task.run("compile")

    module = modules |> hd() |> String.split(".") |> Module.concat()

    case Code.ensure_compiled(module) do
      {:module, _} -> :ok
      {:error, reason} -> Mix.raise("cannot load #{inspect(module)}: #{inspect(reason)}")
    end

    output = Path.expand(opts[:output])
    File.mkdir_p!(Path.dirname(output))
    File.write!(output, LiveLift.Client.Compiler.compile_module(module))
    Mix.shell().info("Generated #{Path.relative_to_cwd(output)}")
  end
end
