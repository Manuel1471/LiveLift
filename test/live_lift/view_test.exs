defmodule LiveLift.ViewTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  defmodule Score do
    use LiveLift.Client

    client_template("<button $click=\"add\">Add</button><output>{@count}</output>")
    defclient(add(state), do: %{count: state.count + 1})
  end

  test "renders the app template and client ownership boundary" do
    html =
      render_component(&LiveLift.View.island/1,
        id: "score",
        module: Score,
        state: %{count: 4}
      )

    assert html =~ ~s(id="score")
    assert html =~ ~s(phx-hook="LiveLift")
    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(data-live-lift-action="add")
    assert html =~ ~s(data-live-lift-text="count">4</span>)
  end

  test "rejects state that the browser cannot represent safely" do
    assert_raise ArgumentError, ~r/safe integers/, fn ->
      render_component(&LiveLift.View.island/1,
        id: "score",
        module: Score,
        state: %{count: 9_007_199_254_740_992}
      )
    end
  end
end
