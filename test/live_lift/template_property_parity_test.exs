defmodule LiveLift.TemplatePropertyParityTest do
  use ExUnit.Case, async: true

  alias LiveLift.Template
  alias LiveLift.Template.FallbackParser
  alias LiveLift.Template.Parser

  test "1,000 generated template states match server and browser DOM" do
    item =
      StreamData.fixed_map(%{
        id: StreamData.integer(0..100),
        label: StreamData.member_of(["", "<&>", "é", "😀", "a &amp; b"]),
        visible: StreamData.member_of([true, false, nil, 0])
      })

    state =
      StreamData.fixed_map(%{
        label: StreamData.member_of(["", "<&>", "é", "😀", "a &amp; b"]),
        title: StreamData.member_of(["", "<&>", "a &amp; b"]),
        visible: StreamData.member_of([true, false, nil, 0]),
        items: StreamData.uniq_list_of(item, uniq_fun: & &1.id, max_length: 5)
      })

    templates = [
      ~s(<p title="A &amp; B">{@label}</p>),
      ~s(<section :if={@visible} title="{@title}">{@label}</section>),
      ~s(<ul><li :for={item <- @items} :key={item.id}>{@item.label}</li></ul>),
      ~s(<div><p :for={item <- @items} :key={item.id} :if={item.visible}>{@item.label}</p><output>{@label}</output></div>)
    ]

    samples = state |> StreamData.seeded(20_261_106) |> Enum.take(250)

    cases =
      for source <- templates,
          state <- samples do
        tree = Template.compile(source, "property_template.ex")
        html = tree |> Template.render_server(state) |> Phoenix.HTML.safe_to_string()
        %{tree: tree, state: state, html: html}
      end

    assert_dom_parity(cases)
  end

  test "generated native HEEx shapes agree across parsers and DOM renderers" do
    body = [
      ~S(<p title={@title} aria-label={@label}>{@label}<br />A &amp; B</p>),
      ~S(<section id={@id} :if={@visible} class={["base", @active && "active"]}>Hello</section>),
      ~S(<ul><li :for={item <- @items} :if={item.visible} id={item.id}>{item.label}</li></ul>),
      ~S(<.badge label={@title} />),
      ~S(<.card title={@title}><span>{@label}</span></.card>),
      ~S(<button phx-click="open" phx-target={@myself} phx-value-id={@id}>Open</button>),
      ~S'<button phx-click={Phoenix.LiveView.JS.focus(to: {:inner, "#entry"})}>Focus</button>',
      ~S'<button phx-click={Phoenix.LiveView.JS.toggle_class("active")}>Toggle</button>',
      ~S'<button phx-click={Phoenix.LiveView.JS.dispatch("demo:preview", bubbles: false)}>Preview</button>',
      ~S(<input name="query" value={@label} phx-change="validate" phx-debounce="blur" />),
      ~S(<form id="edit" phx-submit="save" phx-change="validate"><textarea name="profile[note]" phx-debounce="100">{@label}</textarea><button type="submit">Save</button></form>),
      ~S(<form id="prefs" phx-submit="save"><input name="note" value={@label} data-live-lift-draft={@scope} /></form>),
      ~S(<div><input type="checkbox" checked={@active} /><select><option selected={@active}>A</option></select></div>)
    ]

    components = %{
      "badge" => %{file: "property_template.ex", line: 1, source: ~S(<strong>{@label}</strong>)},
      "card" => %{
        file: "property_template.ex",
        line: 1,
        source: ~S'<article title={@title}>{render_slot(@inner_block)}</article>'
      }
    }

    variations =
      StreamData.fixed_map(%{
        label: StreamData.member_of(["", "é", "😀", "A & B", ~s(<hello "there">)]),
        title: StreamData.member_of([nil, false, "", "Title", ~s(<A "B">)]),
        visible: StreamData.member_of([true, false, nil, 0]),
        active: StreamData.member_of([true, false, nil]),
        id: StreamData.member_of(["row-a", "row-b"]),
        scope: StreamData.member_of(["record-1", "record-2"]),
        wrappers:
          StreamData.list_of(StreamData.member_of(~w(div section article)), max_length: 4),
        items: StreamData.list_of(StreamData.member_of(["", "one & two", "É"]), max_length: 4)
      })
      |> StreamData.seeded(20_261_124)
      |> Enum.take(80)

    cases =
      for fragment <- body, variation <- variations do
        {wrappers, state} = Map.pop!(variation, :wrappers)

        state =
          Map.update!(state, :items, fn labels ->
            Enum.with_index(labels, 1)
            |> Enum.map(fn {label, index} ->
              %{id: "item-#{index}", label: label, visible: rem(index, 2) == 1}
            end)
          end)

        source = Enum.reduce(wrappers, fragment, &"<#{&1}>\n#{&2}\n</#{&1}>")
        file = "property_template.ex"
        mode = {:liveview, ["open", "validate", "save"], components}
        tree = Parser.parse!(source, file) |> Template.compile_parsed(file, mode)
        fallback = FallbackParser.parse!(source, file) |> Template.compile_parsed(file, mode)

        assert tree == fallback, "Parser disagreement for #{source}"
        html = tree |> Template.render_server(state) |> Phoenix.HTML.safe_to_string()
        %{tree: tree, state: state, html: html}
      end

    assert length(cases) == 1_040
    assert_dom_parity(cases)
  end

  test "unsupported HEEx forms retain source diagnostics under generated nesting" do
    rejected = [
      {~S(<p><b></p>), "E065"},
      {~S(<li :for={item <- @items}>{item.label}</li>), "E060"},
      {~S(<div data-custom={@title}>Text</div>), "E061"},
      {~S(<Other.badge label={@title} />), "E062"},
      {~S(<button phx-click="open" phx-target={@other}>Open</button>), "E063"},
      {~S(<form phx-submit="save"><input name="note" /><input name="note" /></form>), "E063"},
      {~S(<input name="note" data-live-lift-draft="draft" />), "E054"},
      {~S'<button phx-click={Phoenix.LiveView.JS.push("open")}>Open</button>', "E053"}
    ]

    wrappers =
      StreamData.list_of(StreamData.member_of(~w(div section article)), max_length: 5)
      |> StreamData.seeded(20_261_125)
      |> Enum.take(16)

    file = "ineligible_template.ex"
    mode = {:liveview, ["open", "save"]}

    for {fragment, code} <- rejected,
        {tags, index} <- Enum.with_index(wrappers, 40),
        parser <- [Parser, FallbackParser] do
      source = Enum.reduce(tags, fragment, &"<#{&1}>\n#{&2}\n</#{&1}>")

      error =
        assert_raise ArgumentError, fn ->
          parser.parse!(source, file, index) |> Template.compile_parsed(file, mode)
        end

      assert Exception.message(error) =~
               ~r/^#{Regex.escape(file)}:#{index + length(tags)}(?::\d+)?:.*\(#{code}\)/,
             "#{inspect(parser)} returned #{Exception.message(error)} for #{source}"
    end
  end

  test "combined native templates match a fresh render after generated state changes" do
    templates = [
      ~S"""
      <section :if={@visible}>
        <article :for={group <- @groups} id={group.id} title={group.label}>
          <.card title={group.label}>
            <div :for={item <- group.items} :if={item.visible} id={item.id}>
              <.badge label={item.label} />
            </div>
          </.card>
        </article>
      </section>
      """,
      ~S"""
      <main>
        <div :for={group <- @groups} id={group.id}>
          <.card title={group.label}>
            <form :for={item <- group.items} id={item.id} phx-submit="save"
                  phx-target={@myself} phx-value-id={item.id}>
              <input name="profile[note]" value={item.label} data-live-lift-draft={item.id} />
              <textarea name="summary">{@label}</textarea>
              <button type="submit">Save</button>
            </form>
          </.card>
        </div>
      </main>
      """,
      ~S"""
      <div>
        <article :for={item <- @left} id={item.id} :key={item.key}
                 class={["left", item.visible && "active"]}><.badge label={item.label} /></article>
        <article :for={item <- @right} id={item.id} :key={item.key}>
          <p :if={item.visible} title={@label}>{item.label}</p>
        </article>
      </div>
      """,
      ~S"""
      <aside>
        <section :for={group <- @groups} id={group.id}>
          <header><.card title={group.label}>{@label}</.card></header>
          <ul>
            <li :for={item <- group.items} id={item.id}>
              <button phx-click="open" phx-value-id={item.id}>{item.label}</button>
              <button :if={item.visible} phx-click={Phoenix.LiveView.JS.focus()}>Focus</button>
            </li>
          </ul>
        </section>
      </aside>
      """
    ]

    components = %{
      "badge" => %{file: "combined.ex", line: 1, source: ~S(<strong>{@label}</strong>)},
      "card" => %{
        file: "combined.ex",
        line: 1,
        source: ~S'<article title={@title}>{render_slot(@inner_block)}</article>'
      }
    }

    samples =
      StreamData.fixed_map(%{
        count: StreamData.integer(2..5),
        label: StreamData.member_of(["", "é", "< & >", ~s("quoted")]),
        alternate: StreamData.member_of(["Changed", "A & B", "🚀"])
      })
      |> StreamData.seeded(20_261_126)
      |> Enum.take(64)

    cases =
      for source <- templates,
          %{count: count, label: label, alternate: alternate} <- samples do
        file = "combined.ex"
        mode = {:liveview, ["open", "save"], components}
        tree = Parser.parse!(source, file) |> Template.compile_parsed(file, mode)
        assert tree == FallbackParser.parse!(source, file) |> Template.compile_parsed(file, mode)

        items = fn prefix ->
          Enum.map(1..count, fn index ->
            %{id: "#{prefix}-#{index}", key: index, label: label, visible: rem(index, 2) == 0}
          end)
        end

        groups = Enum.map(1..2, &%{id: "group-#{&1}", label: label, items: items.("group-#{&1}")})

        initial = %{
          groups: groups,
          left: items.("left"),
          right: items.("right"),
          label: label,
          visible: true
        }

        reordered = %{
          initial
          | groups: Enum.reverse(groups),
            left: Enum.reverse(initial.left),
            right: tl(initial.right)
        }

        edited = %{
          reordered
          | groups:
              Enum.map(reordered.groups, fn group ->
                items = Enum.reverse(group.items)
                changed = %{hd(items) | label: alternate, visible: !hd(items).visible}
                %{group | items: [changed | tl(items)]}
              end),
            left: [%{hd(reordered.left) | label: alternate} | tl(reordered.left)],
            label: alternate
        }

        hidden = %{edited | visible: false, groups: tl(edited.groups), left: []}
        restored = %{edited | right: initial.right}

        %{
          tree: tree,
          state: initial,
          html: render_html(tree, initial),
          updates:
            Enum.map([reordered, edited, hidden, restored], fn state ->
              %{state: state, html: render_html(tree, state)}
            end)
        }
      end

    assert_dom_parity(cases, updates: 1_024)
  end

  test "native bindings match independent Phoenix HEEx renders" do
    templates = [
      ~S(<main><p :if={@visible} class={["base", @active && "active"]} title={@title}>{@label}</p><input value={@label} /></main>),
      ~S(<ul><li :for={item <- @items} :key={item.id} id={item.id}><.badge label={item.label} /></li></ul>),
      ~S(<.card title={@title}><label for="note">Note</label><textarea id="note">{@label}</textarea></.card>),
      ~S(<form id="prefs" phx-submit="save" phx-change="validate" phx-auto-recover="ignore"><input name="profile[note]" value={@label} data-live-lift-draft={@scope} phx-debounce="blur" /><button type="submit">Save</button></form>),
      ~S'<div><button phx-click={Phoenix.LiveView.JS.focus(to: {:inner, "#entry"})}>Focus</button><button phx-click="open" phx-value-id={@scope}>Open</button><input id="entry" type="checkbox" checked={@active} /></div>'
    ]

    badge = ~S(<strong>{@label}</strong>)
    card = ~S'<article title={@title}>{render_slot(@inner_block)}</article>'
    file = "native_oracle.ex"

    components = %{
      "badge" => %{file: file, line: 1, source: badge},
      "card" => %{file: file, line: 1, source: card}
    }

    samples =
      StreamData.fixed_map(%{
        label: StreamData.member_of(["", ~s(<hello "there">), "R&D", "É", "🚀"]),
        title: StreamData.member_of([nil, false, "A & B"]),
        visible: StreamData.member_of([nil, false, true, 0]),
        active: StreamData.member_of([nil, false, true]),
        scope: StreamData.member_of(["record-a", "record-b"]),
        items: StreamData.list_of(StreamData.member_of(["Tea", "É", "R&D"]), max_length: 4)
      })
      |> StreamData.seeded(20_261_127)
      |> Enum.take(64)

    cases =
      Enum.flat_map(Enum.with_index(templates), fn {source, index} ->
        module = Module.concat(__MODULE__, "NativeOracle#{index}")

        Module.create(
          module,
          quote do
            use Phoenix.Component

            def render(var!(assigns)), do: sigil_H(unquote({:<<>>, [], [source]}), [])
            defp badge(var!(assigns)), do: sigil_H(unquote({:<<>>, [], [badge]}), [])
            defp card(var!(assigns)), do: sigil_H(unquote({:<<>>, [], [card]}), [])
          end,
          Macro.Env.location(__ENV__)
        )

        tree = Template.compile_liveview(source, file, ["open", "save", "validate"], components)

        Enum.map(samples, fn state ->
          state =
            Map.update!(state, :items, fn items ->
              Enum.map(Enum.with_index(items, 1), fn {label, index} ->
                %{id: "item-#{index}", label: label}
              end)
            end)

          updated = %{
            state
            | label: "#{state.label}!",
              active: state.active != true,
              visible: state.visible in [nil, false],
              items: Enum.reverse(state.items)
          }

          first_render = independent_render(tree, state, module)

          Map.merge(first_render, %{
            tree: tree,
            updates: [independent_render(tree, updated, module)]
          })
        end)
      end)

    assert_dom_parity(cases, updates: 320, phoenix_renders: 640)
  end

  defp independent_render(tree, state, module) do
    phoenix_html =
      state |> module.render() |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

    %{state: state, html: render_html(tree, state), phoenixHTML: phoenix_html}
  end

  defp render_html(tree, state),
    do: tree |> Template.render_server(state) |> Phoenix.HTML.safe_to_string()

  defp assert_dom_parity(cases, expected \\ []) do
    file =
      Path.join(
        System.tmp_dir!(),
        "live_lift_template_parity_#{System.unique_integer([:positive])}.json"
      )

    try do
      File.write!(file, Jason.encode!(cases))
      script = Path.expand("../../bench/template_parity.mjs", __DIR__)
      {output, status} = System.cmd("node", [script, file], stderr_to_stdout: true)
      assert status == 0, output
      assert output =~ "#{length(cases)} template cases matched"
      if updates = expected[:updates], do: assert(output =~ "#{updates} template updates matched")

      if phoenix_renders = expected[:phoenix_renders],
        do: assert(output =~ "#{phoenix_renders} Phoenix HEEx renders matched")
    after
      File.rm(file)
    end
  end
end
