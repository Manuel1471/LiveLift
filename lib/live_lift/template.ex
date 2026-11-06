defmodule LiveLift.Template do
  @moduledoc """
  Compiles a small Hologram-inspired template syntax for client islands.

  This first slice supports text interpolation (`{@field}`) and click actions
  (`$click="action"`). Interpolations are text only; dynamic attributes and
  arbitrary Elixir expressions are not supported.
  """

  @field ~r/\{@([a-zA-Z_][a-zA-Z0-9_]*)\}/
  @action ~r/\$click="([a-zA-Z_][a-zA-Z0-9_]*)"/

  @spec compile(String.t()) :: String.t()
  def compile(source) when is_binary(source) do
    if Regex.match?(~r/<[^>]*\{@[^}]+\}[^>]*>/s, source) do
      raise ArgumentError, "client template interpolation is supported only in text nodes"
    end

    html =
      source
      |> then(&Regex.replace(@action, &1, "data-live-lift-action=\"\\1\""))
      |> then(&Regex.replace(@field, &1, "<span data-live-lift-text=\"\\1\"></span>"))

    if String.contains?(html, ["$click", "{@"]) do
      raise ArgumentError, "unsupported client template syntax"
    end

    html
  end

  @spec render_server(String.t(), map()) :: Phoenix.HTML.safe()
  def render_server(compiled_html, state) when is_binary(compiled_html) and is_map(state) do
    html =
      Regex.replace(~r/<span data-live-lift-text="([^"]+)"><\/span>/, compiled_html, fn _,
                                                                                        field ->
        value =
          Enum.find_value(state, fn {key, value} ->
            if is_atom(key) and Atom.to_string(key) == field, do: {:ok, value}
          end)

        case value do
          {:ok, value} ->
            escaped =
              value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

            "<span data-live-lift-text=\"#{field}\">#{escaped}</span>"

          nil ->
            raise ArgumentError, "missing client state field: #{field}"
        end
      end)

    Phoenix.HTML.raw(html)
  end
end
