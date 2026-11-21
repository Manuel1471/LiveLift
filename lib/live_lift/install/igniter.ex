defmodule LiveLift.Install.Igniter do
  @moduledoc false

  alias Igniter.Code.{Common, Function, Keyword}
  alias LiveLift.Install.Assets
  alias Rewrite.Source
  alias Sourceror.Zipper

  @compile {:no_warn_undefined, [Igniter, Common, Function, Keyword, Source, Zipper]}

  def install(igniter) do
    igniter
    |> Igniter.update_file("assets/js/app.js", fn source ->
      with {:ok, content} <- Assets.install_hook(Source.get(source, :content)) do
        Source.update(source, :content, content)
      end
    end)
    |> Igniter.update_elixir_file("mix.exs", &update_aliases/1)
    |> ignore_assets()
  end

  defp update_aliases(zipper) do
    with {:ok, zipper} <- update_alias(zipper, :"assets.build"),
         {:ok, zipper} <- update_alias(Zipper.topmost(zipper), :"assets.deploy") do
      {:ok, zipper}
    end
  end

  defp update_alias(zipper, name) do
    with {:ok, aliases} <- Function.move_to_defp(zipper, :aliases, 0),
         {:ok, steps} <- aliases |> Common.rightmost() |> Keyword.get_key(name),
         list = Common.maybe_move_to_single_child_block(steps),
         true <- is_list(Zipper.node(list)),
         positions = list_items(list),
         commands = Enum.map(positions, &command/1),
         true <- Enum.all?(commands, &is_binary/1),
         [esbuild] <- indexes_of(commands, "esbuild"),
         true <- Enum.all?(indexes_of(commands, "phx.digest"), &(&1 > esbuild)) do
      case indexes_of(commands, "live_lift.compile") do
        [] ->
          {:ok, positions |> Enum.at(esbuild) |> Zipper.insert_left(Assets.compile_command())}

        [index] when index < esbuild ->
          if Enum.at(commands, index) in [
               Assets.compile_command(),
               Assets.compile_command() <> " --split"
             ],
             do: {:ok, list},
             else: unsupported_alias(name)

        _ ->
          unsupported_alias(name)
      end
    else
      _ -> unsupported_alias(name)
    end
  end

  defp list_items(list) do
    list |> Zipper.down() |> Stream.iterate(&Zipper.right/1) |> Enum.take_while(&(not is_nil(&1)))
  end

  defp command(zipper) do
    case Zipper.node(zipper) do
      {:__block__, _, [command]} when is_binary(command) -> command
      command when is_binary(command) -> command
      _ -> nil
    end
  end

  defp indexes_of(commands, name) do
    for {command, index} <- Enum.with_index(commands),
        List.first(String.split(command)) == name,
        do: index
  end

  defp unsupported_alias(name) do
    {:error,
     "unsupported #{name} alias; use a literal list with a single esbuild command, or integrate LiveLift before esbuild using docs/phoenix-integration.md"}
  end

  defp ignore_assets(igniter) do
    if Igniter.exists?(igniter, ".gitignore") do
      Igniter.update_file(igniter, ".gitignore", fn source ->
        Source.update(source, :content, Assets.ignore_generated(Source.get(source, :content)))
      end)
    else
      igniter
    end
  end
end
