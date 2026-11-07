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
    assert html =~ ~s(data-live-lift-server-revision="0")
    assert html =~ ~s(data-live-lift-action="add")
    assert html =~ ~s(<!--live-lift:text-->4<!--live-lift:end-->)
  end

  test "includes a validated server snapshot revision" do
    html =
      render_component(&LiveLift.View.island/1,
        id: "score",
        module: Score,
        state: %{count: 4, saved: 3},
        server_fields: [:saved],
        server_revision: 7
      )

    assert html =~ ~s(data-live-lift-server-revision="7")
    assert html =~ ~s(data-live-lift-server-fields="[&quot;saved&quot;]")

    assert_raise ArgumentError, ~r/server_revision must be a non-negative safe integer/, fn ->
      render_component(&LiveLift.View.island/1,
        id: "score",
        module: Score,
        state: %{count: 4, saved: 3},
        server_fields: [:saved],
        server_revision: -1
      )
    end
  end

  test "rejects state that the browser cannot represent safely" do
    assert_raise ArgumentError, ~r/unsupported LiveLift state value/, fn ->
      render_component(&LiveLift.View.island/1,
        id: "score",
        module: Score,
        state: %{count: 9_007_199_254_740_992}
      )
    end
  end

  test "accepts nested browser-safe state and rejects unsafe keys" do
    assert LiveLift.State.validate!(%{items: [%{id: "a", done: false}]}) ==
             %{items: [%{id: "a", done: false}]}

    assert_raise ArgumentError, ~r/unsafe LiveLift state key/, fn ->
      LiveLift.State.validate!(%{__proto__: 1})
    end
  end

  test "enforces list and total state size limits" do
    assert LiveLift.State.validate!(%{items: List.duplicate(nil, 10_000)}) |> map_size() == 1

    assert_raise ArgumentError, ~r/list length limit exceeded/, fn ->
      LiveLift.State.validate!(%{items: List.duplicate(nil, 10_001)})
    end

    too_many_fields = Map.new(1..1_025, fn index -> {"field_#{index}", nil} end)

    assert_raise ArgumentError, ~r/map field limit exceeded/, fn ->
      LiveLift.State.validate!(%{item: too_many_fields})
    end

    assert_raise ArgumentError, ~r/state size limit exceeded/, fn ->
      LiveLift.State.validate!(%{text: String.duplicate("é", 524_289)})
    end

    assert_raise ArgumentError, ~r/state size limit exceeded/, fn ->
      LiveLift.State.validate!(%{
        groups: List.duplicate(%{items: List.duplicate(nil, 1_000)}, 50)
      })
    end
  end

  test "accepts browser-safe primitive state" do
    html =
      render_component(&LiveLift.View.island/1,
        id: "score",
        module: Score,
        state: %{count: nil, label: "ready", active: true}
      )

    assert html =~ ~s(<!--live-lift:text--><!--live-lift:end-->)
    assert html =~ ~s(&quot;label&quot;:&quot;ready&quot;)
  end
end
