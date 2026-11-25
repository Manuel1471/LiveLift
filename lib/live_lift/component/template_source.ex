defmodule LiveLift.Component.TemplateSource do
  @moduledoc false

  def colocated_path(module_file, module_name) do
    basename = module_name |> String.split(".") |> List.last()

    # The auditor receives source AST names. Resolve only literal module names
    # and choose the same single-template convention as Phoenix.
    if Regex.match?(~r/\A[A-Z][a-zA-Z0-9_]*\z/, basename) do
      directory = module_file |> Path.expand() |> Path.dirname()
      pattern = Macro.underscore(basename) <> ".html"
      expected = Path.join(directory, pattern <> ".heex")

      with [^expected] <- Phoenix.Template.find_all(directory, pattern),
           {:ok, %{type: :regular}} <- File.lstat(expected) do
        expected
      else
        _ -> nil
      end
    end
  end
end
