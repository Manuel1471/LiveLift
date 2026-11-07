defmodule LiveLift.ComponentTest do
  use ExUnit.Case, async: false
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

  defmodule ChainedCounter do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<output>{@count} {@label}</output>"

    @client true
    def handle_event("advance", _params, socket) do
      {:noreply,
       socket
       |> assign(:count, socket.assigns.count + 1)
       |> update(:count, &(&1 + 2))
       |> assign(:label, "ready")}
    end

    @client true
    def handle_event("direct", _params, socket) do
      {:noreply, assign(update(socket, :count, &(&1 + 1)), :label, "direct")}
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

    assert {:reply, %{revision: 1, ack_seq: 7, state: %{count: 2}}, duplicate} =
             Counter.handle_event("inc", %{"_live_lift_seq" => 7}, next)

    assert duplicate.assigns.count == 2

    assert_raise ArgumentError, ~r/invalid LiveLift event sequence/, fn ->
      Counter.handle_event("inc", %{"_live_lift_seq" => "bad"}, next)
    end
  end

  test "rejects oversized and unsafe optimistic event parameters" do
    socket = %Phoenix.LiveView.Socket{assigns: %{count: 1, id: "counter", __changed__: %{}}}

    assert_raise ArgumentError, ~r/event parameter limit exceeded/, fn ->
      params = Map.new(1..65, fn index -> {"field_#{index}", "x"} end)
      Counter.handle_event("inc", Map.put(params, "_live_lift_seq", 1), socket)
    end

    assert_raise ArgumentError, ~r/event parameter size limit exceeded/, fn ->
      Counter.handle_event("inc", %{"note" => String.duplicate("é", 32_769)}, socket)
    end

    for key <- ~w(__proto__ constructor prototype) do
      assert_raise ArgumentError, ~r/unsafe LiveLift event parameter/, fn ->
        Counter.handle_event("inc", %{key => "x"}, socket)
      end
    end
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

  test "chained assign and update match the original server handler" do
    cases = [-10, 0, 7]

    expected =
      Enum.map(cases, fn count ->
        socket = %Phoenix.LiveView.Socket{
          assigns: %{count: count, label: "old", id: "chained", __changed__: %{}}
        }

        for event <- ["advance", "direct"] do
          {:reply, %{state: state}, _} = ChainedCounter.handle_event(event, %{}, socket)
          state
        end
      end)

    javascript = LiveLift.Client.Compiler.compile_module(ChainedCounter)

    path =
      Path.join(System.tmp_dir!(), "live_lift_chain_#{System.unique_integer([:positive])}.mjs")

    try do
      File.write!(
        path,
        javascript <>
          "\nconsole.log(JSON.stringify(#{Jason.encode!(cases)}.map(count => ['advance', 'direct'].map(event => actions[event]({count, label: 'old'})))));\n"
      )

      {output, 0} = System.cmd("node", [path])
      assert Jason.decode!(output) == Jason.decode!(Jason.encode!(expected))
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
    for key <- ~w(__proto__ constructor prototype) do
      assert_raise ArgumentError, ~r/unsafe.ex:1: unsafe phx-value parameter/, fn ->
        LiveLift.Template.compile_liveview(
          ~s(<button phx-click="inc" phx-value-#{key}="x">Go</button>),
          "unsafe.ex",
          ["inc"]
        )
      end
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

  test "global and component switches restore the original LiveView behavior" do
    original_enabled = Application.get_env(:live_lift, :enabled)
    original_disabled = Application.get_env(:live_lift, :disabled_components)

    on_exit(fn ->
      restore_env(:enabled, original_enabled)
      restore_env(:disabled_components, original_disabled)
    end)

    for {setting, value} <- [{:enabled, false}, {:disabled_components, [Counter]}] do
      Application.put_env(:live_lift, :enabled, true)
      Application.put_env(:live_lift, :disabled_components, [])
      Application.put_env(:live_lift, setting, value)

      html =
        render_component(&Counter.render/1,
          id: "counter",
          count: 1,
          myself: %Phoenix.LiveComponent.CID{cid: 1}
        )

      refute html =~ ~s(phx-hook="LiveLift")
      assert html =~ ~s(phx-click="inc")
      socket = %Phoenix.LiveView.Socket{assigns: %{count: 1, id: "counter", __changed__: %{}}}
      assert {:noreply, next} = Counter.handle_event("inc", %{}, socket)
      assert next.assigns.count == 2

      assert {:reply, %{disabled: true}, after_refresh} =
               Counter.handle_event("inc", %{"_live_lift_seq" => 1}, socket)

      assert after_refresh.assigns.count == 2
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:live_lift, key)
  defp restore_env(key, value), do: Application.put_env(:live_lift, key, value)
end
