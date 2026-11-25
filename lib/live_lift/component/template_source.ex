defmodule LiveLift.Component.TemplateSource do
  @moduledoc false

  alias LiveLift.Diagnostic

  def literal([do: {:sigil_H, meta, [{:<<>>, _, parts}, []]}], definition_line)
      when is_list(parts) do
    line = meta[:line] || definition_line

    if Enum.all?(parts, &is_binary/1) do
      template_line = if meta[:delimiter] == "\"\"\"", do: line + 1, else: line
      {:ok, Enum.join(parts), line, template_line}
    else
      {:error, line,
       "@client requires a literal ~H render; move dynamic template construction to the server"}
    end
  end

  def literal(_body, line),
    do: {:error, line, "@client requires render/1 to return a literal ~H template"}

  def literal!(body, file, line) do
    case literal(body, line) do
      {:ok, source, line, template_line} -> {source, line, template_line}
      {:error, line, message} -> Diagnostic.error!("E060", file, line, message)
    end
  end

  def local_components!(definitions) do
    Enum.reduce(definitions, %{}, fn {name, body, file, line}, components ->
      if Map.has_key?(components, name) do
        Diagnostic.error!(
          "E062",
          file,
          line,
          "client function component .#{name} has multiple clauses; move it to the server"
        )
      end

      {source, _line, template_line} = literal!(body, file, line)

      Map.put(components, name, %{
        source: source,
        file: file,
        line: line,
        template_line: template_line
      })
    end)
  end

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
