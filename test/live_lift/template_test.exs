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

  test "rejects interpolation in attributes" do
    assert_raise ArgumentError, ~r/only in text nodes/, fn ->
      Template.compile("<input value=\"{@score}\">")
    end
  end

  test "compiles an explicit server event binding" do
    assert Template.compile("<button $server=\"save_score\">Save</button>") ==
             "<button data-live-lift-server=\"save_score\">Save</button>"
  end
end
