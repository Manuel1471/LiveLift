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
               "<output><span data-live-lift-text=\"score\">12</span></output>"
  end

  test "escapes state in the server render" do
    compiled = Template.compile("<p>{@name}</p>")

    html =
      compiled |> Template.render_server(%{name: "<script>"}) |> Phoenix.HTML.safe_to_string()

    assert html == "<p><span data-live-lift-text=\"name\">&lt;script&gt;</span></p>"
  end

  test "renders supported dynamic attributes and escapes their initial values" do
    compiled = Template.compile(~s(<p class="{@style}" title="{@title}">{@name}</p>))

    assert hd(compiled).tag == "p"
    assert Enum.map(hd(compiled).attrs, & &1.name) == ["class", "title"]

    assert compiled
           |> Template.render_server(%{style: "hot", title: ~s(<"), name: nil})
           |> Phoenix.HTML.safe_to_string() ==
             ~s(<p class="hot" data-live-lift-bind-class="style" title="&lt;&quot;" data-live-lift-bind-title="title"><span data-live-lift-text="name"></span></p>)
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
    assert html =~ ~s(data-live-lift-text="item.name">A</span>)
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
    assert html =~ ~s(<strong><span data-live-lift-text="item.name">&lt;A&gt;</span></strong>)
  end
end
