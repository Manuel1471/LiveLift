defmodule LiveLift.Template.Parser do
  @moduledoc false

  # LiveView 1.2 exposes no public HEEx parser. Keep its internal API here and
  # use the bounded LiveLift parser if that API disappears or changes shape.
  alias Phoenix.LiveView.TagEngine.Parser, as: LiveViewParser
  alias LiveLift.Diagnostic
  alias LiveLift.Template.FallbackParser

  @document_prefixes ["<!doctype", "<!DOCTYPE"]

  @spec parse!(String.t(), String.t(), pos_integer()) :: list()
  def parse!(source, file, line \\ 1) do
    if System.get_env("LIVE_LIFT_FORCE_TEMPLATE_FALLBACK") == "1" do
      return_fallback(source, file, line)
    else
      parse_with!(source, file, LiveViewParser, line)
    end
  end

  @doc false
  def parse_with!(source, file, parser, line \\ 1) do
    unless Code.ensure_loaded?(parser) and function_exported?(parser, :parse!, 2) do
      return_fallback(source, file, line)
    else
      opts = [
        tag_handler: Phoenix.LiveView.HTMLEngine,
        file: file,
        line: line,
        strip_eex_comments: true
      ]

      case parser.parse!(source, opts) do
        %{nodes: nodes} when is_list(nodes) ->
          if compatible_nodes?(nodes),
            do: merge_text(nodes),
            else: return_fallback(source, file, line)

        _ ->
          return_fallback(source, file, line)
      end
    end
  rescue
    error in Phoenix.LiveView.TagEngine.Tokenizer.ParseError ->
      Diagnostic.error!(
        "E065",
        file,
        "#{error.line || line}:#{error.column || 1}",
        error.description
      )

    error in MatchError ->
      case error.term do
        {:error, description, %{line: line, column: column}} when is_binary(description) ->
          Diagnostic.error!("E065", file, "#{line}:#{column}", description)

        _ ->
          reraise error, __STACKTRACE__
      end
  end

  # Stripping an EEx comment can split a text token in the middle of an
  # HTML comment or entity. Rejoin the pieces before compiling static text.
  defp merge_text(nodes), do: nodes |> Enum.reduce([], &merge_text_node/2) |> Enum.reverse()

  defp merge_text_node({:text, value, _}, [{:text, previous, meta} | rest]),
    do: [{:text, previous <> value, meta} | rest]

  defp merge_text_node({:block, kind, tag, attrs, children, open, close}, acc),
    do: [{:block, kind, tag, attrs, merge_text(children), open, close} | acc]

  defp merge_text_node(node, acc), do: [node | acc]

  defp compatible_nodes?(nodes), do: Enum.all?(nodes, &compatible_node?/1)

  defp compatible_node?({:text, value, meta}),
    do: is_binary(value) and is_map(meta) and not document_declaration?(value)

  defp compatible_node?({:body_expr, value, meta}), do: is_binary(value) and location?(meta)

  defp compatible_node?({:self_close, type, tag, attrs, meta}),
    do:
      is_atom(type) and is_binary(tag) and is_list(attrs) and
        Enum.all?(attrs, &compatible_attr?/1) and location?(meta)

  defp compatible_node?({:block, type, tag, attrs, children, meta, close}),
    do:
      is_atom(type) and is_binary(tag) and is_list(attrs) and
        Enum.all?(attrs, &compatible_attr?/1) and is_list(children) and
        location?(meta) and location?(close) and compatible_nodes?(children)

  defp compatible_node?(_), do: false

  defp document_declaration?(text) do
    # Phoenix includes doctypes in text tokens without the original location.
    String.contains?(text, @document_prefixes) and
      text |> String.replace(~r/<!--.*?-->/s, " ") |> String.contains?(@document_prefixes)
  end

  defp compatible_attr?({name, nil, meta}),
    do: (is_binary(name) or name == :root) and location?(meta)

  defp compatible_attr?({name, {kind, value, value_meta}, meta}),
    do:
      (is_binary(name) or name == :root) and kind in [:string, :expr] and
        is_binary(value) and is_map(value_meta) and location?(meta)

  defp compatible_attr?(_), do: false

  defp location?(%{line: line, column: column}) when is_integer(line) and is_integer(column),
    do: true

  defp location?(_), do: false

  defp return_fallback(source, file, line), do: FallbackParser.parse!(source, file, line)
end
