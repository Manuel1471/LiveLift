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
end
