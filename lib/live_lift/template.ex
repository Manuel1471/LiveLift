defmodule LiveLift.Template do
  @moduledoc """
  Compiles a small Hologram-inspired template syntax for client islands.

  Supports text bindings, selected dynamic attributes, and click bindings.
  """

  @field ~r/\{@([a-zA-Z_][a-zA-Z0-9_]*)\}/
  @action ~r/\$click="([a-zA-Z_][a-zA-Z0-9_]*)"/
  @server ~r/\$server="([a-zA-Z_][a-zA-Z0-9_]*)"/
  @show ~r/\$show="([a-zA-Z_][a-zA-Z0-9_]*)"/
  @dynamic_attribute ~r/(class|title|aria-label)="\{@([a-zA-Z_][a-zA-Z0-9_]*)\}"/
  @bound_attribute ~r/(class|title|aria-label)="" data-live-lift-bind-\1="([a-zA-Z_][a-zA-Z0-9_]*)"/

  @spec compile(String.t()) :: String.t()
  def compile(source) when is_binary(source) do
    html =
      source
      |> then(&Regex.replace(@dynamic_attribute, &1, "\\1=\"\" data-live-lift-bind-\\1=\"\\2\""))
      |> then(&Regex.replace(@action, &1, "data-live-lift-action=\"\\1\""))
      |> then(&Regex.replace(@server, &1, "data-live-lift-server=\"\\1\""))
      |> then(&Regex.replace(@show, &1, "data-live-lift-show=\"\\1\""))

    if Regex.match?(~r/<[^>]*\{@[^}]+\}[^>]*>/s, html) do
      raise ArgumentError, "unsupported client template attribute interpolation"
    end

    html = Regex.replace(@field, html, "<span data-live-lift-text=\"\\1\"></span>")

    if String.contains?(html, ["$click", "$server", "$show", "{@"]) do
      raise ArgumentError, "unsupported client template syntax"
    end

    html
  end

  @spec render_server(String.t(), map()) :: Phoenix.HTML.safe()
  def render_server(compiled_html, state) when is_binary(compiled_html) and is_map(state) do
    html =
      Regex.replace(~r/data-live-lift-show="([^"]+)"/, compiled_html, fn _, field ->
        value = state_value!(state, field)

        if value in [false, nil],
          do: "data-live-lift-show=\"#{field}\" hidden",
          else: "data-live-lift-show=\"#{field}\""
      end)

    html =
      Regex.replace(@bound_attribute, html, fn _, attribute, field ->
        value = state_value!(state, field)

        escaped =
          value |> display_value() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

        "#{attribute}=\"#{escaped}\" data-live-lift-bind-#{attribute}=\"#{field}\""
      end)

    html =
      Regex.replace(~r/<span data-live-lift-text="([^"]+)"><\/span>/, html, fn _, field ->
        escaped =
          state
          |> state_value!(field)
          |> display_value()
          |> Phoenix.HTML.html_escape()
          |> Phoenix.HTML.safe_to_string()

        "<span data-live-lift-text=\"#{field}\">#{escaped}</span>"
      end)

    Phoenix.HTML.raw(html)
  end

  defp state_value!(state, field) do
    case Enum.find_value(state, fn {key, value} ->
           if is_atom(key) and Atom.to_string(key) == field, do: {:ok, value}
         end) do
      {:ok, value} -> value
      nil -> raise ArgumentError, "missing client state field: #{field}"
    end
  end

  defp display_value(nil), do: ""
  defp display_value(value), do: to_string(value)
end
