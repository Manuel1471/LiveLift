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

    hook_installed? = String.contains?(js, "LiveLift: createClientHook(liveLiftViews)")

    unless hook_installed? or
             (String.contains?(js, "hooks: {...colocatedHooks}") and
                String.contains?(js, "import {hooks as colocatedHooks}")) do
      Mix.raise(
        "unsupported LiveSocket hooks configuration in assets/js/app.js; expected the Phoenix colocatedHooks import and hooks map"
      )
    end

    unless String.contains?(mix, ~s("assets.build": ["compile",)) and
             String.contains?(mix, ~s("assets.deploy": [)) do
      Mix.raise("unsupported Phoenix assets aliases in mix.exs")
    end

    js =
      if hook_installed?,
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
      mix
      |> install_alias("assets.build", ~s("assets.build": ["compile",))
      |> install_alias("assets.deploy", ~s("assets.deploy": [))

    unless String.contains?(js, "import {createClientHook} from \"./live_lift_runtime.js\"") and
             String.contains?(js, "import {views as liveLiftViews} from \"./generated_views.js\"") and
             String.contains?(js, "LiveLift: createClientHook(liveLiftViews)") and
             alias_has_command?(mix, "assets.build") and
             alias_has_command?(mix, "assets.deploy") do
      Mix.raise("LiveLift asset integration is incomplete; no files were changed")
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

  defp install_alias(mix, name, anchor) do
    if alias_has_command?(mix, name) do
      mix
    else
      replacement =
        case name do
          "assets.build" -> ~s("assets.build": ["compile", "#{@compile_command}",)
          "assets.deploy" -> ~s("assets.deploy": ["#{@compile_command}",)
        end

      String.replace(mix, anchor, replacement, global: false)
    end
  end

  defp alias_has_command?(mix, name) do
    case String.split(mix, ~s("#{name}": [), parts: 2) do
      [_, rest] ->
        rest |> String.split("]", parts: 2) |> hd() |> String.contains?(@compile_command)

      _ ->
        false
    end
  end
end
