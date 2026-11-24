defmodule LiveLift.Template.FallbackParser do
  @moduledoc false

  alias LiveLift.Diagnostic

  # Parses only the HEEx-shaped nodes consumed by LiveLift.Template. Every
  # unsupported form raises, so an upstream parser change cannot silently
  # alter browser output.
  @void_tags ~w(area base br col embed hr img input link meta param source track wbr)

  @spec parse!(String.t(), String.t(), pos_integer()) :: list()
  def parse!(source, file, line \\ 1) do
    state = %{rest: source, line: line, column: 1, file: file}
    {nodes, state} = nodes(state, nil, [])

    unless state.rest == "", do: error!(state, "unexpected trailing template content")
    trim_outer_text(nodes)
  end

  defp trim_outer_text([{:text, value, _} | rest] = nodes) do
    if String.trim(value) == "", do: trim_outer_text(rest), else: trim_trailing_text(nodes)
  end

  defp trim_outer_text(nodes), do: trim_trailing_text(nodes)

  defp trim_trailing_text(nodes) do
    nodes
    |> Enum.reverse()
    |> drop_outer_whitespace()
    |> Enum.reverse()
  end

  defp drop_outer_whitespace([{:text, value, _} | rest] = nodes) do
    if String.trim(value) == "", do: drop_outer_whitespace(rest), else: nodes
  end

  defp drop_outer_whitespace(nodes), do: nodes

  defp nodes(%{rest: ""} = state, nil, acc), do: {Enum.reverse(acc), state}
  defp nodes(%{rest: ""} = state, tag, _acc), do: error!(state, "expected </#{tag}>")

  defp nodes(%{rest: "</" <> _} = state, nil, _acc),
    do: error!(state, "unexpected closing tag")

  defp nodes(%{rest: "</" <> _} = state, tag, acc) do
    close_meta = location(state)
    state = advance(state, "</")
    {name, state} = take_while(state, &name_char?/1)
    state = skip_space(state)

    unless name == tag and String.starts_with?(state.rest, ">") do
      error!(state, "expected </#{tag}>, got </#{name}>")
    end

    {Enum.reverse(acc), advance(state, ">"), close_meta}
  end

  defp nodes(%{rest: "<!--" <> _} = state, tag, acc) do
    case :binary.match(state.rest, "-->") do
      {index, 3} ->
        value = binary_part(state.rest, 0, index + 3)
        nodes(advance(state, value), tag, add_text(acc, value))

      :nomatch ->
        error!(state, "expected closing --> for comment")
    end
  end

  defp nodes(%{rest: <<"<!", name::binary-size(7), _::binary>>} = state, _tag, _acc)
       when name in ["doctype", "DOCTYPE"] do
    Diagnostic.error!(
      "E061",
      state.file,
      "#{state.line}:#{state.column}",
      "document declarations belong in the Phoenix root layout"
    )
  end

  defp nodes(%{rest: "<" <> _} = state, tag, acc) do
    {node, state} = element(state)
    nodes(state, tag, [node | acc])
  end

  defp nodes(%{rest: "{" <> _} = state, tag, acc) do
    meta = location(state)
    {expr, state} = balanced(state)
    nodes(state, tag, [{:body_expr, expr, meta} | acc])
  end

  defp nodes(state, tag, acc) do
    {value, state} = take_while(state, &(&1 not in ["<", "{"]))
    nodes(state, tag, add_text(acc, value))
  end

  defp add_text([{:text, previous, meta} | rest], value),
    do: [{:text, previous <> value, meta} | rest]

  defp add_text(acc, value), do: [{:text, value, %{}} | acc]

  defp element(state) do
    meta = location(state)
    state = advance(state, "<")
    {tag, state} = take_while(state, &name_char?/1)

    unless Regex.match?(~r/^(?:[A-Za-z]|[.:][A-Za-z])[A-Za-z0-9_.:-]*$/, tag),
      do: error!(state, "expected a supported HTML tag name")

    type =
      cond do
        String.starts_with?(tag, ":") -> :slot
        String.starts_with?(tag, ".") -> :local_component
        Regex.match?(~r/^[A-Z]$/, String.first(tag)) -> :remote_component
        true -> :tag
      end

    {attrs, closing, state} = attributes(state, [], tag)
    meta = Map.merge(meta, %{tag_name: tag, closing: closing})

    if closing in [:self, :void] do
      {{:self_close, type, tag, attrs, meta}, state}
    else
      {children, state, close_meta} = nodes(state, tag, [])
      {{:block, type, tag, attrs, children, meta, close_meta}, state}
    end
  end

  defp attributes(state, acc, tag) do
    state = skip_space(state)

    cond do
      String.starts_with?(state.rest, "/>") ->
        {Enum.reverse(acc), :self, advance(state, "/>")}

      String.starts_with?(state.rest, ">") ->
        closing = if tag in @void_tags, do: :void, else: :tag
        {Enum.reverse(acc), closing, advance(state, ">")}

      state.rest == "" ->
        error!(state, "unexpected end of tag")

      String.starts_with?(state.rest, "{") ->
        meta = location(state)
        {value, state} = attribute_value(state)
        attributes(state, [{:root, value, meta} | acc], tag)

      true ->
        meta = location(state)
        {name, state} = take_while(state, &attr_char?/1)

        unless Regex.match?(~r/^[:$]?[A-Za-z_][A-Za-z0-9_:.-]*$/, name),
          do: error!(state, "expected a supported attribute name")

        state = skip_space(state)

        {value, state} =
          if String.starts_with?(state.rest, "=") do
            attribute_value(skip_space(advance(state, "=")))
          else
            {nil, state}
          end

        attributes(state, [{name, value, meta} | acc], tag)
    end
  end

  defp attribute_value(%{rest: <<quote, _::binary>>} = state) when quote in [?', ?"] do
    state = advance(state, <<quote>>)
    {value, state} = take_while(state, &(&1 != <<quote>>))

    unless String.starts_with?(state.rest, <<quote>>),
      do: error!(state, "unterminated quoted attribute")

    {{:string, value, %{delimiter: quote}}, advance(state, <<quote>>)}
  end

  defp attribute_value(%{rest: "{" <> _} = state) do
    meta = %{location(state) | column: state.column + 1}
    {expr, state} = balanced(state)
    {{:expr, expr, meta}, state}
  end

  defp attribute_value(state),
    do: error!(state, "expected a quoted attribute value or a braced expression")

  # HEEx counts braces inside quoted values unless a backslash escapes them.
  defp balanced(%{rest: "{" <> _} = state) do
    state = advance(state, "{")
    balanced(state, 1, [])
  end

  defp balanced(%{rest: ""} = state, _depth, _acc),
    do: error!(state, "unterminated Elixir expression")

  defp balanced(%{rest: <<?\\, brace, _::binary>>} = state, depth, acc) when brace in [?{, ?}] do
    escaped = <<?\\, brace>>
    balanced(advance(state, escaped), depth, [escaped | acc])
  end

  defp balanced(state, depth, acc) do
    {char, state} = next(state)

    case char do
      "{" -> balanced(state, depth + 1, [char | acc])
      "}" when depth == 1 -> {acc |> Enum.reverse() |> IO.iodata_to_binary(), state}
      "}" -> balanced(state, depth - 1, [char | acc])
      _ -> balanced(state, depth, [char | acc])
    end
  end

  defp skip_space(%{rest: "\r\n" <> _} = state), do: state |> advance("\r\n") |> skip_space()

  defp skip_space(%{rest: <<char, _::binary>>} = state) when char in [?\s, ?\t, ?\n],
    do: state |> advance(<<char>>) |> skip_space()

  defp skip_space(state), do: state

  defp take_while(state, predicate), do: take_while(state, predicate, [])

  defp take_while(%{rest: ""} = state, _predicate, acc),
    do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), state}

  defp take_while(state, predicate, acc) do
    {char, _} = String.next_codepoint(state.rest)

    if predicate.(char) do
      {_, state} = next(state)
      take_while(state, predicate, [char | acc])
    else
      {acc |> Enum.reverse() |> IO.iodata_to_binary(), state}
    end
  end

  defp next(state) do
    {char, rest} = String.next_codepoint(state.rest)

    {char,
     %{
       state
       | rest: rest,
         line: state.line + if(char == "\n", do: 1, else: 0),
         column: if(char == "\n", do: 1, else: state.column + 1)
     }}
  end

  defp advance(state, text) do
    Enum.reduce(String.codepoints(text), state, fn char, state ->
      {^char, state} = next(state)
      state
    end)
  end

  defp location(state), do: %{line: state.line, column: state.column}
  defp name_char?(char), do: char not in [" ", "\t", "\r", "\n", "/", ">", "="]
  defp attr_char?(char), do: char not in [" ", "\t", "\r", "\n", "/", ">", "="]

  defp error!(state, message),
    do: Diagnostic.error!("E065", state.file, "#{state.line}:#{state.column}", message)
end
