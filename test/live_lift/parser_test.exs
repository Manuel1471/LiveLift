defmodule LiveLift.ParserTest do
  use ExUnit.Case, async: true

  alias LiveLift.Template.Parser
  alias LiveLift.Template
  alias LiveLift.Template.FallbackParser
  alias Phoenix.LiveView.TagEngine.Parser, as: PhoenixParser

  defmodule ChangedParser do
    def parse!(_source, _opts), do: {:ok, []}
  end

  defmodule ChangedNodeParser do
    def parse!(_source, _opts), do: %{nodes: [%{type: :element}]}
  end

  test "a missing LiveView parser uses LiveLift's bounded parser" do
    assert [{:block, :tag, "p", [], [{:text, "Hi", _}], _, _}] =
             Parser.parse_with!("<p>Hi</p>", "view.ex", MissingLiveViewParser)
  end

  test "a changed LiveView parser result uses the same bounded parser" do
    assert [{:block, :tag, "p", [], [{:text, "Hi", _}], _, _}] =
             Parser.parse_with!("<p>Hi</p>", "view.ex", ChangedParser)

    assert [{:block, :tag, "p", [], [{:text, "Hi", _}], _, _}] =
             Parser.parse_with!("<p>Hi</p>", "view.ex", ChangedNodeParser)
  end

  test "fallback rejects malformed markup with source location" do
    assert_raise ArgumentError, ~r/view.ex:1:.*expected <\/b>/, fn ->
      Parser.parse_with!("<p><b></p>", "view.ex", MissingLiveViewParser)
    end

    assert_raise ArgumentError, ~r/view.ex:1:.*expected closing '%>'/, fn ->
      Parser.parse_with!("<%= @name", "view.ex", MissingLiveViewParser)
    end
  end

  test "both parsers explain unsupported EEx body expressions at the opening delimiter" do
    valid_eex = [
      "<%= @name %>",
      "<%= if @shown do %><b>Hi</b><% end %>",
      "<%= for item <- @items do %><b>{item.label}</b><% end %>"
    ]

    for parser <- [PhoenixParser, MissingLiveViewParser] do
      for eex <- valid_eex do
        assert_raise ArgumentError,
                     ~r/view\.ex:42:5:.*use \{\.\.\.\}.*:if.*keyed :for.*\(E061\)/,
                     fn ->
                       Parser.parse_with!("<p>\r\n    #{eex}\n</p>", "view.ex", parser, 41)
                     end
      end

      assert_raise ArgumentError, ~r/view\.ex:42:5:.*expected closing '%>'.*\(E065\)/, fn ->
        Parser.parse_with!("<p>\r\n    <%= @name", "view.ex", parser, 41)
      end

      assert_raise ArgumentError, ~r/view\.ex:41:9:.*EEx expressions.*\(E061\)/, fn ->
        Parser.parse_with!("<p><!-- <%= @name %> --></p>", "view.ex", parser, 41)
      end
    end

    assert [tree, tree] = compile_variants("<p><!-- <%%= @name %> --></p>")
  end

  test "fallback matches LiveView's supported node shapes" do
    samples = [
      ~s(<button $click="inc">Go</button><output>{@count}</output>),
      ~s(<form phx-change="draft"><input name="label" value={@label} /></form>),
      ~s(<ul><li :for={item <- @items} id={item.id}>{item.label}</li></ul>),
      ~s(<p class={["base", @active && "active"]} :if={@shown}>Hi</p>),
      ~s(<LiveLiftDemo.TaskItem item={item} />),
      "\n <div> hi </div>\n",
      ~s(<p>a<!-- note -->b</p>),
      ~s(<input disabled>),
      ~s(<p title="A &amp; B">Tom &amp; Ana</p>)
    ]

    for source <- samples do
      current = Parser.parse!(source, "view.ex") |> normalize()
      fallback = Parser.parse_with!(source, "view.ex", MissingLiveViewParser) |> normalize()
      assert fallback == current
    end
  end

  test "fallback matches the demo's legacy and opted-in component templates" do
    files =
      Path.wildcard("examples/demo/lib/live_lift_demo/*.ex") ++
        Path.wildcard("examples/demo/lib/live_lift_demo_web/live/native_*component.ex")

    templates =
      Enum.flat_map(files, fn file ->
        ast = file |> File.read!() |> Code.string_to_quoted!(file: file)

        {_ast, found} =
          Macro.prewalk(ast, [], fn
            {:client_template, _, [source]} = node, acc when is_binary(source) ->
              {node, [{file, source} | acc]}

            {:sigil_H, _, [{:<<>>, _, parts}, []]} = node, acc when is_list(parts) ->
              if Enum.all?(parts, &is_binary/1),
                do: {node, [{file, Enum.join(parts)} | acc]},
                else: {node, acc}

            node, acc ->
              {node, acc}
          end)

        found
      end)

    assert length(templates) >= 8

    for {file, source} <- templates do
      assert Parser.parse_with!(source, file, MissingLiveViewParser) |> normalize() ==
               Parser.parse!(source, file) |> normalize()
    end
  end

  test "both parsers preserve predicate and bang props on function components" do
    source = ~s(<.badge shown?={@visible} label!="Ready" />)
    components = %{"badge" => %{source: "<span :if={@shown?}>{@label!}</span>", file: "badge.ex"}}

    [adapted, fallback] =
      for parser <- [PhoenixParser, MissingLiveViewParser] do
        tree =
          source
          |> Parser.parse_with!("props.ex", parser)
          |> Template.compile_parsed("props.ex", {:liveview, %{}, components})

        html = tree |> Template.render_server(%{visible: true}) |> Phoenix.HTML.safe_to_string()
        assert html =~ "Ready"

        assert_raise ArgumentError, ~r/props.ex:8:.*remote function component.*\(E062\)/, fn ->
          ~s(<Some.Remote.badge shown?={true} />)
          |> Parser.parse_with!("props.ex", parser, 8)
          |> Template.compile_parsed("props.ex", {:liveview, %{}, components})
        end

        assert_raise ArgumentError, ~r/props.ex:8:.*supports named props only.*\(E062\)/, fn ->
          ~s(<.badge constructor={true} />)
          |> Parser.parse_with!("props.ex", parser, 8)
          |> Template.compile_parsed("props.ex", {:liveview, %{}, components})
        end

        tree
      end

    assert adapted == fallback
  end

  test "fallback compiles and renders the same supported templates" do
    cases = [
      {~s(<button $click="inc">Go</button><output>{@count}</output>), :legacy, %{count: 4}},
      {~s(<ul><li :for={item <- @items} id={item.id}>{item.label}</li></ul>), {:liveview, []},
       %{items: [%{id: "one", label: "<&>"}]}},
      {~s(<p class={["base", @active && "active"]}>{@label}</p>), {:liveview, []},
       %{active: true, label: "Hello"}}
    ]

    for {source, mode, state} <- cases do
      current = Parser.parse!(source, "view.ex") |> Template.compile_parsed("view.ex", mode)

      fallback =
        FallbackParser.parse!(source, "view.ex") |> Template.compile_parsed("view.ex", mode)

      assert fallback == current

      assert fallback |> Template.render_server(state) |> Phoenix.HTML.safe_to_string() ==
               current |> Template.render_server(state) |> Phoenix.HTML.safe_to_string()
    end
  end

  test "attribute formatting and escaped braces compile the same with both parsers" do
    for spacing <- [" ", "\t", "\n", "\r\n\t"],
        equals <- ["=", " = ", "\t=\n\t"],
        title <- [~s('A &amp; "B"'), ~s("A &amp; &quot;B&quot;")] do
      source =
        "<input#{spacing}disabled#{spacing}title#{equals}#{title}#{spacing}" <>
          ~S(value={"literal \} brace"} />)

      [native, fallback] = compile_variants(source)
      assert fallback == native

      html = native |> Template.render_server(%{}) |> Phoenix.HTML.safe_to_string()
      assert html =~ ~s(disabled="")
      assert html =~ ~s(title="A &amp; &quot;B&quot;")
      assert html =~ ~s(value="literal } brace")
    end
  end

  test "both parsers report unsupported attribute forms at the original line" do
    cases = [
      {~S(<input name=query />), "E065"},
      {"<p\rtitle={@label}>Hi</p>", "E065"},
      {~S(<input value={"left} right{"} />), "E065"},
      {~S(<p {@attrs}>Hi</p>), "E061"},
      {~S(<p phx-no-curly-interpolation>{@label}</p>), "E061"}
    ]

    for {source, code} <- cases, parser <- [PhoenixParser, MissingLiveViewParser] do
      assert_raise ArgumentError, ~r/formatting\.ex:31(?::\d+)?:.*\(#{code}\)/, fn ->
        source
        |> Parser.parse_with!("formatting.ex", parser, 31)
        |> Template.compile_parsed("formatting.ex", {:liveview, []})
      end
    end
  end

  test "both parsers locate document declarations and ignore them inside HTML comments" do
    for parser <- [PhoenixParser, MissingLiveViewParser],
        doctype <- ["<!doctype html>", "<!DOCTYPE html>"],
        {source, line, column} <- [
          {doctype <> "<p>Hi</p>", 31, 1},
          {"\n<!-- note -->\r\n" <> doctype <> "\n<p>Hi</p>", 33, 1},
          {"<section>text\n  " <> doctype <> "</section>", 32, 3}
        ] do
      assert_raise ArgumentError,
                   ~r/formatting\.ex:#{line}:#{column}:.*document declarations.*\(E061\)/,
                   fn -> Parser.parse_with!(source, "formatting.ex", parser, 31) end
    end

    source = ~S(<p>A<!-- <!doctype html> {@ignored} -->&#123;literal&#125; {"text \} here"}</p>)
    [native, fallback] = compile_variants(source)
    assert fallback == native
    html = native |> Template.render_server(%{}) |> Phoenix.HTML.safe_to_string()
    assert html =~ ~S(<!-- <!doctype html> {@ignored} -->&#123;literal&#125;)
    assert html =~ "text } here"
  end

  test "both parsers strip server-side HEEx comments and preserve following locations" do
    source = "<p>A<%!-- ignored 🚀\r\n{@ghost} --%>B<!--C<%!-- hidden --> --%>D-->{@label}</p>"

    for parser <- [PhoenixParser, MissingLiveViewParser] do
      assert [{:block, :tag, "p", [], children, _, _}] =
               Parser.parse_with!(source, "comment.ex", parser, 31)

      assert [{:text, "AB<!--CD-->", _}, {:body_expr, "@label", %{line: 32, column: 45}}] =
               children

      assert_raise ArgumentError, ~r/comment.ex:32:4:.*expected closing.*--%>.*\(E065\)/, fn ->
        Parser.parse_with!("<p>\r\n  A<%!-- missing</p>", "comment.ex", parser, 31)
      end

      assert_raise ArgumentError, ~r/comment.ex:31:\d+:.*expected closing.*-->.*\(E065\)/s, fn ->
        Parser.parse_with!("<p><!-- unclosed <%!-- hidden --%></p>", "comment.ex", parser, 31)
      end

      for invalid <- [
            ~S(<p <%!-- bad --%> title="a">A</p>),
            ~S(<p title="A<%!-- bad --%>B">A</p>),
            ~S(<p>{"A<%!-- bad --%>B"}</p>)
          ] do
        assert_raise ArgumentError, ~r/comment.ex:31:\d+:.*\(E065\)/s, fn ->
          Parser.parse_with!(invalid, "comment.ex", parser, 31)
        end
      end
    end

    assert [native, native] = compile_variants(source)

    assert native |> Template.render_server(%{label: "End"}) |> Phoenix.HTML.safe_to_string() ==
             ~S(<p>AB<!--CD--><!--live-lift:text-->End<!--live-lift:end--></p>)

    for tree <- compile_variants("<p>&am<%!-- comment --%>p;</p>") do
      assert tree |> Template.render_server(%{}) |> Phoenix.HTML.safe_to_string() ==
               "<p>&amp;</p>"
    end
  end

  defp compile_variants(source) do
    for parser <- [PhoenixParser, MissingLiveViewParser] do
      source
      |> Parser.parse_with!("formatting.ex", parser, 31)
      |> Template.compile_parsed("formatting.ex", {:liveview, []})
    end
  end

  defp normalize(nodes) when is_list(nodes), do: Enum.map(nodes, &normalize/1)
  defp normalize({:text, value, _}), do: {:text, value}
  defp normalize({:body_expr, value, _}), do: {:body_expr, value}

  defp normalize({:self_close, type, tag, attrs, _}),
    do: {:self_close, type, normalize_tag(type, tag), normalize_attrs(attrs)}

  defp normalize({:block, type, tag, attrs, children, _, _}),
    do: {:block, type, normalize_tag(type, tag), normalize_attrs(attrs), normalize(children)}

  defp normalize_tag(:local_component, tag), do: String.trim_leading(tag, ".")
  defp normalize_tag(_type, tag), do: tag

  defp normalize_attrs(attrs),
    do: Enum.map(attrs, fn {name, value, _} -> {name, normalize_attr(value)} end)

  defp normalize_attr({kind, value, _}), do: {kind, value}
  defp normalize_attr(nil), do: nil
end
