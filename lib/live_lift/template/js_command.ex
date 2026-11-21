defmodule LiveLift.Template.JSCommand do
  @moduledoc false

  alias Phoenix.LiveView.JS

  @target ~r/\A[#.][a-zA-Z_][a-zA-Z0-9_-]{0,63}\z/
  @class ~r/\A[a-zA-Z_][a-zA-Z0-9_-]{0,63}\z/
  @opening_bracket ~r/\A(?:\[|&(?:#0*91(?![0-9])|#[xX]0*5[bB](?![0-9a-fA-F])|lbrack;|lsqb;))/
  @focus [:focus, :focus_first]
  @classes [:add_class, :remove_class, :toggle_class]

  @spec compile!(String.t(), String.t(), pos_integer()) :: {String.t(), boolean()}
  def compile!(source, file, line) do
    with true <- byte_size(source) <= 1024,
         {:ok, ast} <- Code.string_to_quoted(source, file: file, line: line),
         {:ok, js} <- command(ast, 8) do
      preserves_classes? =
        Enum.any?(js.ops, fn [name, _] -> name in ~w(add_class remove_class toggle_class) end)

      {Phoenix.json_library().encode!(js), preserves_classes?}
    else
      _ -> unsupported!(file, line, "use a supported literal Phoenix.LiveView.JS command")
    end
  end

  @spec reject_delayed!(list(), String.t(), pos_integer()) :: :ok
  def reject_delayed!(attrs, file, line) do
    if Enum.any?(attrs, fn {name, _, _} -> name in ~w(phx-debounce phx-throttle) end) do
      unsupported!(file, line, "use class commands without phx-debounce or phx-throttle")
    end

    :ok
  end

  @spec reject_encoded!(String.t(), String.t(), pos_integer()) :: nil
  def reject_encoded!(value, file, line) do
    if Regex.match?(@opening_bracket, value) do
      unsupported!(file, line, "write a named event or a supported literal JS command")
    end
  end

  defp command(_ast, 0), do: :error

  defp command({:|>, _, [source, call]}, remaining) do
    with {:ok, js} <- command(source, remaining - 1) do
      append(call, js)
    end
  end

  defp command(call, _remaining), do: append(call, %JS{})

  defp append({{:., _, [{:__aliases__, _, [:Phoenix, :LiveView, :JS]}, name]}, _, args}, js)
       when name in @focus do
    case args do
      [] -> {:ok, apply(JS, name, [js])}
      [options] -> apply_options(name, [js], options)
      _ -> :error
    end
  end

  defp append(
         {{:., _, [{:__aliases__, _, [:Phoenix, :LiveView, :JS]}, name]}, _, [names | args]},
         js
       )
       when name in @classes and is_binary(names) do
    classes = String.split(names, " ", trim: true)

    with true <- length(classes) in 1..8 and Enum.all?(classes, &Regex.match?(@class, &1)) do
      case args do
        [] -> {:ok, apply(JS, name, [js, names])}
        [options] -> apply_options(name, [js, names], options)
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  defp append(_call, _js), do: :error

  defp apply_options(name, args, []), do: {:ok, apply(JS, name, args ++ [[]])}

  defp apply_options(name, args, [to: {:inner, selector}] = options) when is_binary(selector) do
    if Regex.match?(@target, selector),
      do: {:ok, apply(JS, name, args ++ [options])},
      else: :error
  end

  defp apply_options(_name, _args, _options), do: :error

  defp unsupported!(file, line, reason) do
    raise ArgumentError,
          "#{file}:#{line}: unsupported native click command (E053): #{reason}; " <>
            "or render this binding outside the LiveLift island. See docs/errors/E053.md"
  end
end
