defmodule LiveLift.TemplateTest do
  use ExUnit.Case, async: true

  alias LiveLift.Template

  test "compiles app markup to client bindings and renders initial state" do
    compiled =
      Template.compile("<button $click=\"advance\">Add</button><output>{@score}</output>")

    assert compiled ==
             "<button data-live-lift-action=\"advance\">Add</button>" <>
               "<output><span data-live-lift-text=\"score\"></span></output>"

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

    assert compiled ==
             ~s(<p class="" data-live-lift-bind-class="style" title="" data-live-lift-bind-title="title"><span data-live-lift-text="name"></span></p>)

    assert compiled
           |> Template.render_server(%{style: "hot", title: ~s(<"), name: nil})
           |> Phoenix.HTML.safe_to_string() ==
             ~s(<p class="hot" data-live-lift-bind-class="style" title="&lt;&quot;" data-live-lift-bind-title="title"><span data-live-lift-text="name"></span></p>)
  end

  test "rejects unsupported attribute interpolation" do
    assert_raise ArgumentError, ~r/unsupported client template attribute/, fn ->
      Template.compile("<input value=\"{@score}\">")
    end
  end

  test "compiles an explicit server event binding" do
    assert Template.compile("<button $server=\"save_score\">Save</button>") ==
             "<button data-live-lift-server=\"save_score\">Save</button>"
  end
end
