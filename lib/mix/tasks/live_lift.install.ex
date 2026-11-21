defmodule Mix.Tasks.LiveLift.Install do
  use Mix.Task

  alias LiveLift.Install.Assets

  @shortdoc "Integrates LiveLift assets into a Phoenix 1.8 app"

  @impl Mix.Task
  def run([]) do
    app_js = "assets/js/app.js"
    mix_exs = "mix.exs"

    unless File.regular?(app_js) and File.regular?(mix_exs) do
      Mix.raise("live_lift.install must run in a Phoenix app with assets/js/app.js")
    end

    js = File.read!(app_js)
    mix = File.read!(mix_exs)

    js =
      case Assets.install_hook(js) do
        {:ok, source} -> source
        {:error, message} -> Mix.raise(message)
      end

    unless (alias_has_command?(mix, "assets.build") or
              String.contains?(mix, ~s("assets.build": ["compile",))) and
             (alias_has_command?(mix, "assets.deploy") or
                String.contains?(mix, ~s("assets.deploy": [))) do
      Mix.raise("unsupported Phoenix assets aliases in mix.exs")
    end

    mix =
      mix
      |> install_alias("assets.build", ~s("assets.build": ["compile",))
      |> install_alias("assets.deploy", ~s("assets.deploy": [))

    unless alias_has_command?(mix, "assets.build") and alias_has_command?(mix, "assets.deploy") do
      Mix.raise("LiveLift asset integration is incomplete; no files were changed")
    end

    File.write!(app_js, js)
    File.write!(mix_exs, mix)

    if File.regular?(".gitignore") do
      ignore = ".gitignore" |> File.read!() |> Assets.ignore_generated()
      File.write!(".gitignore", ignore)
    end

    Mix.shell().info("LiveLift assets integrated. Run mix assets.build.")
  end

  def run(_), do: Mix.raise("usage: mix live_lift.install")

  @doc false
  def installer?, do: true

  @doc false
  def supports_umbrella?, do: false

  @doc false
  def info(_argv, _source), do: struct!(Igniter.Mix.Task.Info, extra_args?: true)

  @doc false
  def parse_argv(argv), do: struct!(Igniter.Mix.Task.Args, argv: argv)

  @doc false
  defdelegate igniter(project), to: LiveLift.Install.Igniter, as: :install

  defp install_alias(mix, name, anchor) do
    if alias_has_command?(mix, name) do
      mix
    else
      replacement =
        case name do
          "assets.build" -> ~s("assets.build": ["compile", "#{Assets.compile_command()}",)
          "assets.deploy" -> ~s("assets.deploy": ["#{Assets.compile_command()}",)
        end

      String.replace(mix, anchor, replacement, global: false)
    end
  end

  defp alias_has_command?(mix, name) do
    case String.split(mix, ~s("#{name}": [), parts: 2) do
      [_, rest] ->
        rest |> String.split("]", parts: 2) |> hd() |> String.contains?(Assets.compile_command())

      _ ->
        false
    end
  end
end
