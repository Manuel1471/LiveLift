defmodule LiveLift.ComponentTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]

  defmodule Counter do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns) do
      ~H"""
      <button phx-click="inc" phx-target={@myself}>{@count}</button>
      """
    end

    @client true
    def handle_event("inc", _params, socket) do
      {:noreply, update(socket, :count, &(&1 + 1))}
    end
  end

  defmodule AssignCounter do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<output>{@count}</output>"

    @client true
    def handle_event("add_two", _params, socket) do
      {:noreply, assign(socket, :count, socket.assigns.count + 2)}
    end
  end

  defmodule ParamCounter do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns) do
      ~H"""
      <button phx-click="label" phx-value-label="ready" phx-target={@myself}>{@label}</button>
      """
    end

    @client true
    def handle_event("label", params, socket) do
      {:noreply, assign(socket, :label, params["label"])}
    end
  end

  defmodule PatternCounter do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<output>{@label}</output>"

    @client true
    def handle_event("set", %{"value" => value}, socket) do
      {:noreply, socket |> assign(:label, value)}
    end
  end

  test "uses the real HEEx render and compiles the marked event" do
    html =
      render_component(&Counter.render/1,
        id: "counter",
        count: 1,
        myself: %Phoenix.LiveComponent.CID{cid: 1}
      )

    assert html =~ ~s(phx-click="inc")
    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(data-live-lift-mode="component")
    assert html =~ ">1</button>"
    assert Counter.__live_lift_component_fields__() == [:count]

    javascript = LiveLift.Client.Compiler.compile_registry([Counter])
    assert javascript =~ ~s("LiveLift.ComponentTest.Counter")
    assert javascript =~ "inc: (state)"
    assert javascript =~ ~s("data-live-lift-action")
  end

  test "reply returns the server's authoritative state" do
    socket = %Phoenix.LiveView.Socket{assigns: %{count: 1, id: "counter", __changed__: %{}}}

    assert {:reply, %{revision: 1, ack_seq: 7, state: %{count: 2}}, next} =
             Counter.handle_event("inc", %{"_live_lift_seq" => 7}, socket)

    assert next.assigns.count == 2
  end

  test "assign and update actions agree with generated JavaScript" do
    for {module, action, step} <- [{Counter, "inc", 1}, {AssignCounter, "add_two", 2}] do
      javascript = LiveLift.Client.Compiler.compile_module(module)

      path =
        Path.join(
          System.tmp_dir!(),
          "live_lift_component_#{System.unique_integer([:positive])}.mjs"
        )

      try do
        File.write!(
          path,
          javascript <>
            "\nconsole.log(JSON.stringify([0,1,9].map(count => actions[#{Jason.encode!(action)}]({count}).count)));\n"
        )

        {output, 0} = System.cmd("node", [path])
        assert Jason.decode!(output) == Enum.map([0, 1, 9], &(&1 + step))
      after
        File.rm(path)
      end
    end
  end

  test "phx-value params have the same value in the handler and JavaScript" do
    socket = %Phoenix.LiveView.Socket{assigns: %{label: "", id: "param", __changed__: %{}}}

    assert {:reply, %{state: %{label: "ready"}}, _} =
             ParamCounter.handle_event("label", %{"label" => "ready"}, socket)

    javascript = LiveLift.Client.Compiler.compile_module(ParamCounter)

    path =
      Path.join(System.tmp_dir!(), "live_lift_params_#{System.unique_integer([:positive])}.mjs")

    try do
      File.write!(
        path,
        javascript <>
          "\nconsole.log(JSON.stringify(actions.label({label: ''}, {params: {label: 'ready'}})));\n"
      )

      {output, 0} = System.cmd("node", [path])
      assert Jason.decode!(output) == %{"label" => "ready"}
    after
      File.rm(path)
    end
  end

  test "a flat pattern and socket pipe keep native handler semantics" do
    socket = %Phoenix.LiveView.Socket{assigns: %{label: "", id: "pattern", __changed__: %{}}}

    assert {:reply, %{state: %{label: "pattern"}}, _} =
             PatternCounter.handle_event("set", %{"value" => "pattern"}, socket)

    javascript = LiveLift.Client.Compiler.compile_module(PatternCounter)

    path =
      Path.join(System.tmp_dir!(), "live_lift_pattern_#{System.unique_integer([:positive])}.mjs")

    try do
      File.write!(
        path,
        javascript <>
          "\nconsole.log(JSON.stringify(actions.set({label: ''}, {params: {value: 'pattern'}})));\n"
      )

      {output, 0} = System.cmd("node", [path])
      assert Jason.decode!(output) == %{"label" => "pattern"}
    after
      File.rm(path)
    end
  end

  test "unsupported marked handlers fail with a source location" do
    source = """
    defmodule LiveLift.ComponentTest.Unsupported do
      use Phoenix.LiveComponent
      use LiveLift
      def render(assigns), do: ~H"<output>{@count}</output>"
      @client true
      def handle_event("send", _params, socket), do: {:noreply, send(self(), socket)}
    end
    """

    assert_raise ArgumentError,
                 ~r/unsupported.ex:6: @client currently supports assign\/3 and update\/3/,
                 fn ->
                   Code.compile_string(source, "unsupported.ex")
                 end
  end

  test "rejects unsafe native event parameter names at compilation" do
    assert_raise ArgumentError, ~r/unsafe.ex:1: unsafe phx-value parameter __proto__/, fn ->
      LiveLift.Template.compile_liveview(
        ~s(<button phx-click="inc" phx-value-__proto__="x">Go</button>),
        "unsafe.ex",
        ["inc"]
      )
    end
  end

  test "rejects nested or duplicate native form names" do
    assert_raise ArgumentError, ~r/form.ex:1: @client form requires flat safe input names/, fn ->
      LiveLift.Template.compile_liveview(
        ~s(<form phx-submit="save"><input name="user[name]" /></form>),
        "form.ex",
        ["save"]
      )
    end

    assert_raise ArgumentError, ~r/form.ex:1: @client form has duplicate input names/, fn ->
      LiveLift.Template.compile_liveview(
        ~s(<form phx-submit="save"><input name="value" /><input name="value" /></form>),
        "form.ex",
        ["save"]
      )
    end

    assert_raise ArgumentError, ~r/form.ex:1: @client form has a checkbox/, fn ->
      LiveLift.Template.compile_liveview(
        ~s(<form phx-submit="save"><input type="checkbox" name="agree" /></form>),
        "form.ex",
        ["save"]
      )
    end
  end
end
