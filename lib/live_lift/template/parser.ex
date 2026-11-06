defmodule LiveLift.Template.Parser do
  @moduledoc false

  # LiveView 1.2 exposes no public HEEx parser. Keep its internal API here so
  # a future LiveView change has one migration point.
  alias Phoenix.LiveView.TagEngine.Parser, as: LiveViewParser

  @spec parse!(String.t(), String.t()) :: list()
  def parse!(source, file) do
    source
    |> LiveViewParser.parse!(tag_handler: Phoenix.LiveView.HTMLEngine, file: file)
    |> Map.fetch!(:nodes)
  rescue
    error in Phoenix.LiveView.TagEngine.Tokenizer.ParseError ->
      raise ArgumentError, Exception.message(error)
  end
end
