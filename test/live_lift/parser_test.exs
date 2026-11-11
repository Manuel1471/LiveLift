defmodule LiveLift.ParserTest do
  use ExUnit.Case, async: true

  alias LiveLift.Template.Parser
  alias LiveLift.Template
  alias LiveLift.Template.FallbackParser

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

    assert_raise ArgumentError, ~r/view.ex:1:.*supported HTML tag name/, fn ->
      Parser.parse_with!("<%= @name %>", "view.ex", MissingLiveViewParser)
    end
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

  defp normalize(nodes) when is_list(nodes), do: Enum.map(nodes, &normalize/1)
  defp normalize({:text, value, _}), do: {:text, value}
  defp normalize({:body_expr, value, _}), do: {:body_expr, value}

  defp normalize({:self_close, type, tag, attrs, _}),
    do: {:self_close, type, tag, normalize_attrs(attrs)}

  defp normalize({:block, type, tag, attrs, children, _, _}),
    do: {:block, type, tag, normalize_attrs(attrs), normalize(children)}

  defp normalize_attrs(attrs),
    do: Enum.map(attrs, fn {name, value, _} -> {name, normalize_attr(value)} end)

  defp normalize_attr({kind, value, _}), do: {kind, value}
  defp normalize_attr(nil), do: nil
end
