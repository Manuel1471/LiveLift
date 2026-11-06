defmodule LiveLift.Template.Expression do
  @moduledoc false

  def parse(source, file, line) when is_binary(source) do
    case Code.string_to_quoted(source, file: file, line: line) do
      {:ok, quoted} ->
        convert(quoted, file, line)

      {:error, {_location, message, token}} ->
        raise ArgumentError, "#{file}:#{line}: invalid client expression: #{message} #{token}"
    end
  end

  def eval(%{type: "literal", value: value}, _scope), do: value

  def eval(%{type: "path", root: root, fields: fields}, scope) do
    value = Map.fetch!(scope, root)

    Enum.reduce(fields, value, fn field, current ->
      unless is_map(current),
        do: raise(ArgumentError, "cannot read #{field} from a non-map value")

      case Enum.find_value(current, fn {key, value} ->
             if (is_atom(key) and Atom.to_string(key) == field) or key == field,
               do: {:ok, value}
           end) do
        {:ok, value} -> value
        nil -> raise ArgumentError, "missing client field: #{field}"
      end
    end)
  end

  def eval(%{type: "map", entries: entries}, scope) do
    Map.new(entries, fn {key, expr} -> {String.to_atom(key), eval(expr, scope)} end)
  end

  defp convert(value, _file, _line)
       when is_integer(value) or is_binary(value) or is_boolean(value) or is_nil(value),
       do: %{type: "literal", value: value}

  defp convert({:@, _, [{name, _, _}]}, _file, _line) when is_atom(name),
    do: %{type: "path", root: "state", fields: [Atom.to_string(name)]}

  defp convert({name, _, context}, _file, _line)
       when is_atom(name) and (is_atom(context) or is_nil(context)),
       do: %{type: "path", root: Atom.to_string(name), fields: []}

  defp convert({{:., _, [source, field]}, _, []}, file, line) when is_atom(field) do
    path = convert(source, file, line)

    if path.type == "path" do
      %{path | fields: path.fields ++ [Atom.to_string(field)]}
    else
      unsupported!(file, line, source)
    end
  end

  defp convert({:%{}, _, entries}, file, line) when is_list(entries) do
    %{
      type: "map",
      entries:
        Enum.map(entries, fn
          {key, value} when is_atom(key) -> {Atom.to_string(key), convert(value, file, line)}
          other -> unsupported!(file, line, other)
        end)
    }
  end

  defp convert(other, file, line), do: unsupported!(file, line, other)

  defp unsupported!(file, line, other) do
    raise ArgumentError,
          "#{file}:#{line}: unsupported client expression: #{Macro.to_string(other)}"
  end
end
