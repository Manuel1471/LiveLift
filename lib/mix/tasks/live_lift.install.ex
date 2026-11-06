defmodule Mix.Tasks.LiveLift.Install do
  use Mix.Task

  @shortdoc "Integrates LiveLift assets into a Phoenix 1.8 app"
  @compile_command "live_lift.compile --output assets/js/generated_views.js"
  @imports "import {createClientHook} from \"./live_lift_runtime.js\"\nimport {views as liveLiftViews} from \"./generated_views.js\"\n"

  @impl Mix.Task
  def run([]) do
    app_js = "assets/js/app.js"
    mix_exs = "mix.exs"

    unless File.regular?(app_js) and File.regular?(mix_exs) do
      Mix.raise("live_lift.install must run in a Phoenix app with assets/js/app.js")
    end

    js = File.read!(app_js)
    mix = File.read!(mix_exs)

    unless String.contains?(js, "hooks: {...colocatedHooks}") or
             String.contains?(js, "LiveLift: createClientHook(liveLiftViews)") do
      Mix.raise("unsupported LiveSocket hooks configuration in assets/js/app.js")
    end

    unless String.contains?(mix, ~s("assets.build": ["compile",)) and
             String.contains?(mix, ~s("assets.deploy": [)) do
      Mix.raise("unsupported Phoenix assets aliases in mix.exs")
    end

    js =
      if String.contains?(js, "LiveLift: createClientHook(liveLiftViews)"),
        do: js,
        else:
          js
          |> String.replace(
            "import {hooks as colocatedHooks}",
            @imports <> "import {hooks as colocatedHooks}",
            global: false
          )
          |> String.replace(
            "hooks: {...colocatedHooks}",
            "hooks: {...colocatedHooks, LiveLift: createClientHook(liveLiftViews)}",
            global: false
          )

    mix =
      if String.contains?(mix, @compile_command) do
        mix
      else
        mix
        |> String.replace(
          ~s("assets.build": ["compile",),
          ~s("assets.build": ["compile", "#{@compile_command}",),
          global: false
        )
        |> String.replace(
          ~s("assets.deploy": [),
          ~s("assets.deploy": ["#{@compile_command}",),
          global: false
        )
      end

    File.write!(app_js, js)
    File.write!(mix_exs, mix)

    if File.regular?(".gitignore") do
      ignore = File.read!(".gitignore")

      ignore =
        Enum.reduce(
          [
            "/assets/js/generated_views.js",
            "/assets/js/generated_views.js.map",
            "/assets/js/live_lift_runtime.js"
          ],
          ignore,
          fn entry, content ->
            if entry in String.split(content, "\n"), do: content, else: content <> "\n" <> entry
          end
        )

      File.write!(".gitignore", String.trim_trailing(ignore) <> "\n")
    end

    Mix.shell().info("LiveLift assets integrated. Run mix assets.build.")
  end

  def run(_), do: Mix.raise("usage: mix live_lift.install")
end
