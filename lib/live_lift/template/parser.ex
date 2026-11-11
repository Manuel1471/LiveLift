defmodule LiveLift.Template.Parser do
  @moduledoc false

  # LiveView 1.2 exposes no public HEEx parser. Keep its internal API here so
  # a future LiveView change has one migration point.
  alias Phoenix.LiveView.TagEngine.Parser, as: LiveViewParser

  @spec parse!(String.t(), String.t()) :: list()
  def parse!(source, file) do
    parse_with!(source, file, LiveViewParser)
  end

  @doc false
  def parse_with!(source, file, parser) do
    unless Code.ensure_loaded?(parser) and function_exported?(parser, :parse!, 2) do
      raise ArgumentError,
            "#{file}:1: this Phoenix LiveView version has no compatible HEEx parser; use a supported LiveView 1.2.x version or keep this component on the server"
    end

    case parser.parse!(source, tag_handler: Phoenix.LiveView.HTMLEngine, file: file) do
      %{nodes: nodes} when is_list(nodes) ->
        nodes

      _ ->
        raise ArgumentError,
              "#{file}:1: the Phoenix LiveView HEEx parser returned an unsupported tree; use a supported LiveView 1.2.x version or keep this component on the server"
    end
  rescue
    error in Phoenix.LiveView.TagEngine.Tokenizer.ParseError ->
      raise ArgumentError, Exception.message(error)
  end
end
