defmodule LiveLift.Client.Assets do
  @moduledoc false

  @runtime_directory Path.expand("../../../assets/js/live_lift", __DIR__)
  @npm_runtime "live-lift-assets"

  def runtime(output, opts) do
    source = File.read!(Path.join(@runtime_directory, "client_hook.js"))

    _ = Application.load(:live_lift)
    version = :live_lift |> Application.spec(:vsn) |> to_string()
    digest = :crypto.hash(:sha256, [version, <<0>>, source]) |> Base.encode16(case: :lower)
    identifier = String.replace(version, ~r/[^A-Za-z0-9_]/, "_")
    binding = "__liveLiftRuntime_#{identifier}_#{digest}"

    if opts[:npm_runtime] do
      {@npm_runtime, binding, nil}
    else
      destination =
        Path.expand(
          opts[:runtime_output] || Path.join(Path.dirname(output), "live_lift_runtime.js")
        )

      registry_files = [output, output <> ".map", types_path(output)]

      if destination in registry_files or types_path(destination) in registry_files do
        Mix.raise(
          "registry and runtime outputs must use different JavaScript and declaration paths"
        )
      end

      specifier = relative_import(destination, Path.dirname(output))
      {specifier, binding, {destination, source}}
    end
  end

  def write_runtime(nil, _binding), do: :ok

  def write_runtime({destination, source}, binding) do
    File.mkdir_p!(Path.dirname(destination))
    File.write!(destination, source <> "\nexport {createClientHook as #{binding}};\n")

    File.cp!(
      Path.join(@runtime_directory, "client_hook.d.ts"),
      types_path(destination)
    )

    Mix.shell().info("Copied #{Path.relative_to_cwd(destination)}")
  end

  def link(specifier, binding) do
    "export {#{binding} as __liveLiftRuntime} from #{Jason.encode!(specifier)};\n"
  end

  def write_registry_types(output, specifier) do
    File.write!(
      types_path(output),
      "import type {ViewRegistry} from #{Jason.encode!(specifier)};\n" <>
        "export declare const views: ViewRegistry;\n"
    )
  end

  defp types_path(js) do
    extension = if Path.extname(js) == ".mjs", do: ".d.mts", else: ".d.ts"
    Path.rootname(js) <> extension
  end

  defp relative_import(destination, from) do
    [root | target] = Path.split(destination)
    [source_root | directory] = Path.split(from)

    unless root == source_root do
      Mix.raise("registry and runtime outputs must be on the same filesystem root")
    end

    relative_import_parts(target, directory)
    |> Enum.join("/")
    |> then(fn path -> if String.starts_with?(path, "../"), do: path, else: "./" <> path end)
  end

  defp relative_import_parts([part | target], [part | directory]),
    do: relative_import_parts(target, directory)

  defp relative_import_parts(target, directory),
    do: Enum.map(directory, fn _ -> ".." end) ++ target
end
