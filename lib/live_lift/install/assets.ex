defmodule LiveLift.Install.Assets do
  @moduledoc false

  @runtime_import ~s(import {createClientHook} from "./live_lift_runtime.js")
  @views_import ~s(import {views as liveLiftViews} from "./generated_views.js")
  @colocated_import "import {hooks as colocatedHooks}"
  @plain_hooks "hooks: {...colocatedHooks}"
  @installed_hook "LiveLift: createClientHook(liveLiftViews)"
  @compile_command "live_lift.compile --output assets/js/generated_views.js"

  def compile_command, do: @compile_command

  def install_hook(source) do
    cond do
      String.contains?(source, @installed_hook) ->
        if Enum.all?(
             [@runtime_import, @views_import, @installed_hook],
             &occurs_once?(source, &1)
           ),
           do: {:ok, source},
           else: {:error, "LiveLift hook imports are incomplete or duplicated"}

      occurs_once?(source, @colocated_import) and occurs_once?(source, @plain_hooks) and
          not String.contains?(source, [@runtime_import, @views_import]) ->
        installed =
          source
          |> String.replace(
            @colocated_import,
            "#{@runtime_import}\n#{@views_import}\n#{@colocated_import}"
          )
          |> String.replace(@plain_hooks, "hooks: {...colocatedHooks, #{@installed_hook}}")

        {:ok, installed}

      true ->
        {:error,
         "unsupported LiveSocket hooks configuration in assets/js/app.js; expected the Phoenix colocatedHooks import and hooks map. See docs/phoenix-integration.md"}
    end
  end

  def ignore_generated(source) do
    Enum.reduce(
      [
        "/assets/js/generated_views.js",
        "/assets/js/generated_views.js.map",
        "/assets/js/generated_views.d.ts",
        "/assets/js/live_lift_runtime.d.ts",
        "/assets/js/live_lift_runtime.js"
      ],
      source,
      fn entry, content ->
        if entry in String.split(content, "\n"),
          do: content,
          else: String.trim_trailing(content, "\n") <> "\n" <> entry <> "\n"
      end
    )
  end

  defp occurs_once?(source, snippet), do: length(:binary.matches(source, snippet)) == 1
end
