defmodule LiveLift.TemplateTest do
  use ExUnit.Case, async: true

  alias LiveLift.Template

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

  test "keeps directive-like text and existing HTML entities literal" do
    tree = Template.compile(~s(<p title="A &amp; B">$click="go"</p>))

    assert tree |> Template.render_server(%{}) |> Phoenix.HTML.safe_to_string() ==
             ~s(<p title="A &amp; B">$click="go"</p>)
  end
end
