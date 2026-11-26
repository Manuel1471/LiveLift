alias LiveLift.Template
alias LiveLift.Template.{FallbackParser, Parser}
alias Phoenix.LiveView.TagEngine.Parser, as: LiveViewParser

cases = [
  {"pre", "literal LF", "\nfirst\nsecond", ""},
  {"pre", "literal CRLF", "\r\nfirst\r\nsecond", ""},
  {"pre", "leading comment", "<!-- note -->\nfirst", ""},
  {"pre", "binding LF and CRLF", "{@value}", "\nfirst\r\nsecond"},
  {"pre", "binding without a leading newline", "{@value}", "first\nsecond"},
  {"textarea", "literal LF", "\nfirst\nsecond", ""},
  {"textarea", "literal CRLF", "\r\nfirst\r\nsecond", ""},
  {"textarea", "binding LF and CRLF", "{@value}", "\nfirst\r\nsecond"},
  {"textarea", "binding without a leading newline", "{@value}", "first\nsecond"}
]

fixtures =
  cases
  |> Enum.with_index()
  |> Enum.map(fn {{tag, name, body, value}, index} ->
    source = "<#{tag}>#{body}</#{tag}>"
    file = "preformatted_text_spike.heex"
    module = Module.concat(LiveLift.PreformattedTextSpike, "Fixture#{index}")

    Module.create(
      module,
      quote do
        use Phoenix.Component
        def render(var!(assigns)), do: sigil_H(unquote({:<<>>, [], [source]}), [])
      end,
      Macro.Env.location(__ENV__)
    )

    mode = {:liveview, []}

    tree =
      source |> Parser.parse_with!(file, LiveViewParser) |> Template.compile_parsed(file, mode)

    fallback = source |> FallbackParser.parse!(file) |> Template.compile_parsed(file, mode)
    if tree != fallback, do: raise("Parser disagreement in #{tag}: #{name}")

    state = %{value: value}
    html = state |> module.render() |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    %{name: "#{tag}: #{name}", tag: tag, tree: tree, state: state, html: html}
  end)

IO.puts(Jason.encode!(fixtures))
