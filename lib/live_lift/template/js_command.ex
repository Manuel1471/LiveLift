defmodule LiveLift.Template.JSCommand do
  @moduledoc false

  alias Phoenix.LiveView.JS

  @target ~r/\A[#.][a-zA-Z_][a-zA-Z0-9_-]{0,63}\z/
  @opening_bracket ~r/\A(?:\[|&(?:#0*91(?![0-9])|#[xX]0*5[bB](?![0-9a-fA-F])|lbrack;|lsqb;))/
  @commands [:focus, :focus_first]

  @spec compile!(String.t(), String.t(), pos_integer()) :: String.t()
  def compile!(source, file, line) do
    with true <- byte_size(source) <= 1024,
         {:ok, ast} <- Code.string_to_quoted(source, file: file, line: line),
         {:ok, js} <- command(ast, 8) do
      Phoenix.json_library().encode!(js)
    else
      _ -> unsupported!(file, line, "use literal Phoenix.LiveView.JS.focus or focus_first")
    end
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
       when name in @commands do
    case args do
      [] ->
        {:ok, apply(JS, name, [js])}

      [[to: {:inner, selector}] = options] when is_binary(selector) ->
        if Regex.match?(@target, selector),
          do: {:ok, apply(JS, name, [js, options])},
          else: :error

      _ ->
        :error
    end
  end

  defp append(_call, _js), do: :error

  defp unsupported!(file, line, reason) do
    raise ArgumentError,
          "#{file}:#{line}: unsupported native click command (E053): #{reason}; " <>
            "or render this binding outside the LiveLift island. See docs/errors/E053.md"
  end
end
