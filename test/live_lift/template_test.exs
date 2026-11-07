defmodule LiveLift.TemplateTest do
  use ExUnit.Case, async: true

  alias LiveLift.Template

  defmodule Item do
    use LiveLift.Client.Component
    client_template("<strong>{@item.name}</strong>")
  end

  test "compiles app markup to client bindings and renders initial state" do
    compiled =
      Template.compile("<button $click=\"advance\">Add</button><output>{@score}</output>")

    assert hd(compiled).tag == "button"

    assert hd(compiled).attrs == [
             %{name: "data-live-lift-action", type: "static", value: "advance"}
           ]

    assert compiled |> Template.render_server(%{score: 12}) |> Phoenix.HTML.safe_to_string() ==
             "<button data-live-lift-action=\"advance\">Add</button>" <>
               "<output><!--live-lift:text-->12<!--live-lift:end--></output>"
  end

  test "escapes state in the server render" do
    compiled = Template.compile("<p>{@name}</p>")

    html =
      compiled |> Template.render_server(%{name: "<script>"}) |> Phoenix.HTML.safe_to_string()

    assert html == "<p><!--live-lift:text-->&lt;script&gt;<!--live-lift:end--></p>"
  end

  test "renders supported dynamic attributes and escapes their initial values" do
    compiled = Template.compile(~s(<p class="{@style}" title="{@title}">{@name}</p>))

    assert hd(compiled).tag == "p"
    assert Enum.map(hd(compiled).attrs, & &1.name) == ["class", "title"]

    assert compiled
           |> Template.render_server(%{style: "hot", title: ~s(<"), name: nil})
           |> Phoenix.HTML.safe_to_string() ==
             ~s(<p class="hot" data-live-lift-bind-class="style" title="&lt;&quot;" data-live-lift-bind-title="title"><!--live-lift:text--><!--live-lift:end--></p>)
  end

  test "native HEEx class lists and expression attributes match server semantics" do
    tree =
      Template.compile_liveview(
        ~s(<section class={["base", @active && "active"]} title={@title}><input value={@draft} /></section>),
        "native.ex",
        []
      )

    assert tree
           |> Template.render_server(%{active: false, title: nil, draft: ""})
           |> Phoenix.HTML.safe_to_string() ==
             ~s(<section class="base "><input value=""></section>)

    assert tree
           |> Template.render_server(%{active: nil, title: false, draft: nil})
           |> Phoenix.HTML.safe_to_string() ==
             ~s(<section class="base "><input></section>)

    assert tree
           |> Template.render_server(%{active: true, title: ~s(<"), draft: "ready"})
           |> Phoenix.HTML.safe_to_string() ==
             ~s(<section class="base active" title="&lt;&quot;"><input value="ready"></section>)

    assert_raise ArgumentError,
                 ~r/native.ex:1: unsupported client expression attribute: href/,
                 fn ->
                   Template.compile_liveview(~s(<a href={@url}>Open</a>), "native.ex", [])
                 end

    nested = Template.compile_liveview(~s(<p class={[[nil], @classes]}>Hi</p>), "native.ex", [])

    assert nested
           |> Template.render_server(%{classes: [false, "ready"]})
           |> Phoenix.HTML.safe_to_string() == ~s(<p class="ready">Hi</p>)
  end

  test "native HEEx :for uses the repeated element id as its client key" do
    tree =
      Template.compile_liveview(
        ~s(<ul><li :for={item <- @items} id={item.id}>{item.label}</li></ul>),
        "native_list.ex",
        []
      )

    assert tree
           |> Template.render_server(%{
             items: [%{id: "row-1", label: "One"}, %{id: "row-2", label: "<Two>"}]
           })
           |> Phoenix.HTML.safe_to_string() =~
             ~s(<li id="row-1" data-live-lift-key="row-1")

    assert tree
           |> Template.render_server(%{items: [%{id: "row-2", label: "<Two>"}]})
           |> Phoenix.HTML.safe_to_string() =~ "&lt;Two&gt;"

    assert_raise ArgumentError, ~r/native_list.ex:1: @client :for requires id=\{item.id\}/, fn ->
      Template.compile_liveview(
        ~s(<li :for={item <- @items}>{item.label}</li>),
        "native_list.ex",
        []
      )
    end

    assert_raise ArgumentError, ~r/native_list.ex:1: @client :for requires id=\{item.id\}/, fn ->
      Template.compile_liveview(
        ~s(<li :for={item <- @items} id={@id}>{item.label}</li>),
        "native_list.ex",
        []
      )
    end
  end

  test "native dynamic phx-value attributes render item event params" do
    tree =
      Template.compile_liveview(
        ~s(<button :for={item <- @items} id={item.id} phx-click="remove" phx-value-id={item.id} phx-target={@myself}>Remove</button>),
        "native_params.ex",
        ["remove"]
      )

    html =
      tree
      |> Template.render_server(%{items: [%{id: "row-<&"}]})
      |> Phoenix.HTML.safe_to_string()

    assert html =~ ~s(phx-value-id="row-&lt;&amp;")
    assert html =~ ~s(data-live-lift-action="remove")

    assert_raise ArgumentError, ~r/native_params.ex:1: unsafe phx-value parameter/, fn ->
      Template.compile_liveview(
        ~s(<button phx-value-__proto__={@id}>Remove</button>),
        "native_params.ex",
        []
      )
    end
  end

  test "rejects marked form phx-change before it can diverge from LiveView" do
    assert_raise ArgumentError,
                 ~r/form.ex:1: @client form phx-change is not supported yet; use phx-submit/,
                 fn ->
                   Template.compile_liveview(
                     ~s(<form phx-change="edit"><input name="label" /></form>),
                     "form.ex",
                     ["edit"]
                   )
                 end

    assert_raise ArgumentError,
                 ~r/form.ex:1: @client form phx-change is not supported yet; use phx-submit/,
                 fn ->
                   Template.compile_liveview(
                     ~s(<form><input name="label" phx-change="edit" /></form>),
                     "form.ex",
                     ["edit"]
                   )
                 end
  end

  test "rejects unsupported attribute interpolation" do
    assert_raise ArgumentError, ~r/unsupported client template attribute/, fn ->
      Template.compile("<a href=\"{@score}\">Open</a>")
    end

    assert_raise ArgumentError, ~r/unsupported client template attribute/, fn ->
      Template.compile("<p data-class=\"{@style}\"></p>")
    end
  end

  test "compiles an explicit server event binding" do
    assert Template.compile("<button $server=\"save_score\">Save</button>")
           |> Template.render_server(%{})
           |> Phoenix.HTML.safe_to_string() ==
             "<button data-live-lift-server=\"save_score\">Save</button>"
  end

  test "renders conditional visibility with Elixir truthiness" do
    compiled = Template.compile(~s(<p $show="visible">Hello</p>))

    assert hd(compiled).attrs == [
             %{name: "data-live-lift-show", type: "static", value: "visible"}
           ]

    assert compiled |> Template.render_server(%{visible: false}) |> Phoenix.HTML.safe_to_string() ==
             ~s(<p data-live-lift-show="visible" hidden>Hello</p>)

    assert compiled |> Template.render_server(%{visible: 0}) |> Phoenix.HTML.safe_to_string() ==
             ~s(<p data-live-lift-show="visible">Hello</p>)
  end

  test "binds a progress value for visualizations" do
    compiled = Template.compile(~s(<progress value="{@score}" max="20"></progress>))

    assert hd(compiled).tag == "progress"
    assert hd(compiled).attrs |> hd() |> Map.fetch!(:type) == "dynamic"

    assert compiled |> Template.render_server(%{score: 12}) |> Phoenix.HTML.safe_to_string() ==
             ~s(<progress value="12" data-live-lift-bind-value="score" max="20"></progress>)
  end

  test "reports malformed markup and unsupported syntax with source location" do
    assert_raise ArgumentError, ~r/view.ex:1/, fn ->
      Template.compile("<div><p></div>", "view.ex")
    end

    assert_raise ArgumentError, ~r/view.ex:1: unsupported client directive: \$hover/, fn ->
      Template.compile(~s(<button $hover="go">Go</button>), "view.ex")
    end
  end

  test "rejects executable HTML in client templates" do
    assert_raise ArgumentError, ~r/unsafe client template tag/, fn ->
      Template.compile("<script>alert(1)</script>", "view.ex")
    end

    assert_raise ArgumentError, ~r/unsafe client attribute/, fn ->
      Template.compile("<button onclick=\"alert(1)\">Go</button>", "view.ex")
    end

    assert_raise ArgumentError, ~r/unsafe client attribute/, fn ->
      Template.compile("<a href=\"javascript:alert(1)\">Go</a>", "view.ex")
    end

    for href <- [
          "java&#x73;cript:alert(1)",
          "javascript&#58;alert(1)",
          "javascript&colon;alert(1)",
          "java&#9;script:alert(1)",
          "java\tscript:alert(1)",
          "data:text/html,hello"
        ] do
      assert_raise ArgumentError, ~r/view.ex:1: unsafe client attribute: href/, fn ->
        Template.compile(~s(<a href="#{href}">Go</a>), "view.ex")
      end
    end

    assert_raise ArgumentError, ~r/unsafe client attribute: src/, fn ->
      Template.compile(~s(<img src="data:image/svg+xml,example" />), "view.ex")
    end

    assert_raise ArgumentError, ~r/unsafe client attribute: xlink:href/, fn ->
      Template.compile(~s|<svg><a xlink:href="javascript:alert(1)">x</a></svg>|, "view.ex")
    end

    assert_raise ArgumentError, ~r/unsafe client attribute: href/, fn ->
      Template.compile(~s|<a HREF="javascript:alert(1)">x</a>|, "view.ex")
    end

    assert_raise ArgumentError, ~r/unsafe client attribute: xml:base/, fn ->
      Template.compile(~s(<svg xml:base="/assets/"></svg>), "view.ex")
    end

    for tag <- ~w(base meta link style foreignObject animate) do
      assert_raise ArgumentError, ~r/unsafe client template tag/, fn ->
        source = if tag in ~w(base meta link), do: "<#{tag} />", else: "<#{tag}></#{tag}>"
        Template.compile(source, "view.ex")
      end
    end

    assert [_] = Template.compile(~s(<a href="https://example.com/?a=1&amp;b=2">Go</a>))
    assert [_] = Template.compile(~s(<a href="/relative/path">Go</a>))
    assert [_] = Template.compile(~s(<a href="mailto:hello@example.com">Go</a>))
  end

  test "1,000 encoded JavaScript URL variants fail compilation" do
    for seed <- 1..1_000 do
      disguised =
        "javascript:"
        |> String.to_charlist()
        |> Enum.map_reduce(:rand.seed_s(:exsss, {seed, seed * 2, seed * 3}), fn char, random ->
          {choice, next} = :rand.uniform_s(4, random)

          piece =
            case choice do
              1 -> <<char>>
              2 -> "&##{char};"
              3 -> "&#x#{Integer.to_string(char, 16)};"
              4 -> if char == ?:, do: "&colon;", else: <<char>>
            end

          {piece, next}
        end)
        |> elem(0)
        |> Enum.join()

      assert_raise ArgumentError, ~r/unsafe client attribute: href/, fn ->
        Template.compile(~s|<a href="#{disguised}alert(1)">Go</a>|, "fuzz.ex")
      end
    end
  end

  test "keeps directive-like text and existing HTML entities literal" do
    tree = Template.compile(~s(<p title="A &amp; B">$click="go"</p>))

    assert tree |> Template.render_server(%{}) |> Phoenix.HTML.safe_to_string() ==
             ~s(<p title="A &amp; B">$click="go"</p>)
  end

  test "renders keyed lists and conditional nodes from nested state" do
    tree =
      Template.compile(
        ~s(<ul><li :for={item <- @items} :key={item.id} :if={item.visible}>{@item.name}</li></ul>)
      )

    html =
      tree
      |> Template.render_server(%{
        items: [%{id: "a", name: "A", visible: true}, %{id: "b", name: "B", visible: false}]
      })
      |> Phoenix.HTML.safe_to_string()

    assert html =~ ~s(data-live-lift-key="a")
    assert html =~ ~s(<!--live-lift:text-->A<!--live-lift:end-->)
    refute html =~ ~s(data-live-lift-key="b")
  end

  test "requires keys on repeated nodes and rejects duplicate keys" do
    assert_raise ArgumentError, ~r/:for requires :key/, fn ->
      Template.compile(~s(<li :for={item <- @items}>{@item}</li>), "list.ex")
    end

    tree = Template.compile(~s(<li :for={item <- @items} :key={item.id}>{@item.name}</li>))

    assert_raise ArgumentError, ~r/duplicate client list key/, fn ->
      Template.render_server(tree, %{items: [%{id: "a", name: "A"}, %{id: "a", name: "B"}]})
    end
  end

  test "namespaces keys from sibling loops" do
    tree =
      Template.compile(
        ~s(<div><p :for={item <- @first} :key={item.id}>{@item.name}</p><p :for={item <- @second} :key={item.id}>{@item.name}</p></div>)
      )

    html =
      tree
      |> Template.render_server(%{first: [%{id: 1, name: "A"}], second: [%{id: 1, name: "B"}]})
      |> Phoenix.HTML.safe_to_string()

    assert html =~ ~s(data-live-lift-key="1")
    assert length(Regex.scan(~r/data-live-lift-key="1"/, html)) == 2
    ids = Regex.scan(~r/data-live-lift-node-id="([^"]+)"/, html, capture: :all_but_first)
    assert ids |> Enum.map(&hd/1) |> Enum.uniq() |> length() == 2
  end

  test "renders checkbox, option, and textarea values with HTML semantics" do
    tree =
      Template.compile(
        ~s(<div><input type="checkbox" checked={@enabled} /><select><option value="a" selected={@selected}>A</option><option value="b">B</option></select><textarea>{@draft}</textarea></div>)
      )

    html =
      tree
      |> Template.render_server(%{enabled: true, selected: false, draft: ~s(A & "B")})
      |> Phoenix.HTML.safe_to_string()

    assert html =~ ~s(<input type="checkbox" checked>)
    refute html =~ " selected"
    assert html =~ ~s(<textarea>A &amp; &quot;B&quot;</textarea>)

    assert_raise ArgumentError, ~r/checked requires a boolean or nil/, fn ->
      Template.render_server(tree, %{enabled: "true", selected: false, draft: "x"})
    end
  end

  test "requires native keyboard-accessible controls for events" do
    assert_raise ArgumentError, ~r/click events require a native button/, fn ->
      Template.compile(~s(<div $click="add">Add</div>), "controls.ex")
    end

    assert_raise ArgumentError, ~r/input events require a native form control/, fn ->
      Template.compile(~s(<span $input="edit">Edit</span>), "controls.ex")
    end

    assert_raise ArgumentError, ~r/submit events require a form/, fn ->
      Template.compile(~s(<div $submit="save">Save</div>), "controls.ex")
    end
  end

  test "renders app-defined components with props inside keyed lists" do
    tree =
      Template.compile(
        ~s(<ul><li :for={item <- @items} :key={item.id}><LiveLift.TemplateTest.Item item={item} /></li></ul>)
      )

    html =
      tree
      |> Template.render_server(%{items: [%{id: 1, name: "<A>"}]})
      |> Phoenix.HTML.safe_to_string()

    assert html =~ ~s(data-live-lift-key="1")
    assert html =~ ~s(<strong><!--live-lift:text-->&lt;A&gt;<!--live-lift:end--></strong>)
  end
end
