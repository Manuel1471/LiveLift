defmodule LiveLift.ComponentTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [render_component: 2]

  @doc false
  def telemetry_handler(name, measures, metadata, parent) do
    send(parent, {name, measures, metadata})
  end

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

    def handle_event("reset", _params, socket) do
      {:noreply, assign(socket, :count, 0)}
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

  defmodule UpdatedCounter do
    use Phoenix.LiveComponent
    use LiveLift

    def update(%{value: value}, socket), do: {:ok, assign(socket, :count, value * 2)}
    def render(assigns), do: ~H"<output>{@count}</output>"

    @client true
    def handle_event("inc", _, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
  end

  defmodule BatchedCounter do
    use Phoenix.LiveComponent
    use LiveLift

    def update_many(entries) do
      Enum.map(entries, fn {assigns, socket} -> assign(socket, assigns) end)
    end

    def render(assigns), do: ~H"<output>{@count}</output>"

    @client true
    def handle_event("inc", _, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
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

  defmodule LocalBadge do
    use Phoenix.LiveComponent
    use LiveLift

    attr(:label, :string, required: true)
    attr(:visible, :boolean, required: true)

    defp badge(assigns) do
      ~H"""
      <span :if={@visible} class="badge">{@label}</span>
      """
    end

    attr(:label, :string, required: true)
    slot(:inner_block, required: true)

    defp card(assigns) do
      ~H"""
      <div class="card" title={@label}>{render_slot(@inner_block)}</div>
      """
    end

    def render(assigns) do
      ~H"""
      <section><.card label="Card"><.badge label={@label} visible={@visible} /></.card><.badge label="Ready" visible={true} /><.badge label={"A & B"} visible={true} /><button phx-click="toggle" phx-target={@myself}>Toggle</button></section>
      """
    end

    @client true
    def handle_event("toggle", _params, socket) do
      {:noreply, assign(socket, :visible, !socket.assigns.visible)}
    end
  end

  defmodule ChainedCounter do
    use Phoenix.LiveComponent
    use LiveLift

    def mount(socket), do: {:ok, assign(socket, :label, "mounted"), temporary_assigns: []}

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

  defmodule MapEditor do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<output>{@item.label}</output>"

    @client true
    def handle_event("merge", params, socket) do
      {:noreply, update(socket, :item, &Map.merge(&1, %{label: params["label"]}))}
    end

    @client true
    def handle_event("clear", _params, socket) do
      {:noreply, update(socket, :item, &Map.delete(&1, :extra))}
    end
  end

  defmodule OptionalDraft do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns) do
      ~H"""
      <button phx-click="init" phx-target={@myself}>Initialize</button><p :if={@ready}>{@draft}</p>
      """
    end

    @client true
    def handle_event("init", _params, socket) do
      {:noreply,
       socket
       |> assign_new(:draft, fn -> socket.assigns.prefix <> " draft" end)
       |> assign(:ready, true)}
    end
  end

  defmodule OptionalLazy do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<button phx-click='init' phx-target={@myself}>Init</button>"

    @client true
    def handle_event("init", _params, socket),
      do: {:noreply, assign_new(socket, :draft, fn -> rem(1, 0) end)}
  end

  test "assign_new adds an absent field and preserves existing nil or value" do
    assert OptionalDraft.__live_lift_component_optional_fields__() == [:draft]
    assert Enum.sort(OptionalDraft.__live_lift_component_fields__()) == [:draft, :prefix, :ready]

    html =
      render_component(&OptionalDraft.render/1,
        id: "optional",
        prefix: "fresh",
        ready: false,
        myself: %Phoenix.LiveComponent.CID{cid: 1}
      )

    assert html =~ ~s(&quot;prefix&quot;:&quot;fresh&quot;)
    refute html =~ ">fresh</p>"

    states = [
      %{ready: false, prefix: "fresh"},
      %{ready: false, prefix: "fresh", draft: nil},
      %{ready: false, prefix: "fresh", draft: "existing"}
    ]

    expected =
      Enum.map(states, fn state ->
        socket = %Phoenix.LiveView.Socket{
          assigns: Map.merge(state, %{id: "optional", __changed__: %{}})
        }

        {:reply, %{state: result}, _} =
          OptionalDraft.handle_event("init", %{"_live_lift_seq" => 1}, socket)

        result
      end)

    javascript = LiveLift.Client.Compiler.compile_module(OptionalDraft)

    script =
      javascript <>
        "\nconsole.log(JSON.stringify(#{Jason.encode!(states)}.map(state => actions.init(state))));"

    {output, 0} = System.cmd("node", ["--input-type=module", "--eval", script])
    assert Jason.decode!(output) == Jason.decode!(Jason.encode!(expected))

    assert expected == [
             %{ready: true, prefix: "fresh", draft: "fresh draft"},
             %{ready: true, prefix: "fresh", draft: nil},
             %{ready: true, prefix: "fresh", draft: "existing"}
           ]
  end

  test "assign_new does not evaluate a failing fallback when the key exists" do
    socket = %Phoenix.LiveView.Socket{assigns: %{draft: nil, id: "lazy", __changed__: %{}}}

    assert {:reply, %{state: %{draft: nil}}, _} =
             OptionalLazy.handle_event("init", %{"_live_lift_seq" => 1}, socket)

    script =
      LiveLift.Client.Compiler.compile_module(OptionalLazy) <>
        "\nconsole.log(JSON.stringify(actions.init({draft: null})));"

    assert {"{\"draft\":null}\n", 0} =
             System.cmd("node", ["--input-type=module", "--eval", script])
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

  test "an instance identifier is stable on the component socket and unique per mount" do
    initial = %Phoenix.LiveView.Socket{assigns: %{count: 0, id: "counter", __changed__: %{}}}

    assert {:ok, first} = Counter.mount(initial)
    assert {:ok, second} = Counter.mount(initial)
    refute first.assigns.__live_lift_instance == second.assigns.__live_lift_instance

    assert {:reply, _, updated} = Counter.handle_event("inc", %{"_live_lift_seq" => 1}, first)
    assert updated.assigns.__live_lift_instance == first.assigns.__live_lift_instance

    assert {:ok, custom, [temporary_assigns: []]} = ChainedCounter.mount(initial)
    assert custom.assigns.label == "mounted"
    assert is_binary(custom.assigns.__live_lift_instance)
  end

  test "custom updates keep the first revision and advance only for rendered state" do
    {:ok, initial} = UpdatedCounter.mount(%Phoenix.LiveView.Socket{})
    {:ok, mounted} = UpdatedCounter.update(%{value: 2}, initial)
    assert mounted.assigns.count == 4
    assert Map.get(mounted.assigns, :__live_lift_revision, 0) == 0

    {:ok, changed} = UpdatedCounter.update(%{value: 3}, mounted)
    assert changed.assigns.count == 6
    assert changed.assigns.__live_lift_revision == 1
    assert {:ok, ^changed} = UpdatedCounter.update(%{value: 3}, changed)
  end

  test "batched updates advance the revision of only the changed component" do
    {:ok, a} = BatchedCounter.mount(%Phoenix.LiveView.Socket{})
    {:ok, b} = BatchedCounter.mount(%Phoenix.LiveView.Socket{})
    [a, b] = BatchedCounter.update_many([{%{count: 1}, a}, {%{count: 2}, b}])
    [updated, unchanged] = BatchedCounter.update_many([{%{count: 3}, a}, {%{count: 2}, b}])
    assert updated.assigns.count == 3
    assert updated.assigns.__live_lift_revision == 1
    assert unchanged == b
  end

  test "reply returns the server's authoritative state" do
    socket = %Phoenix.LiveView.Socket{assigns: %{count: 1, id: "counter", __changed__: %{}}}

    assert {:reply, %{revision: 1, ack_seq: 1, state: %{count: 2}}, next} =
             Counter.handle_event("inc", %{"_live_lift_seq" => 1}, socket)

    assert next.assigns.count == 2

    assert {:reply, %{revision: 1, ack_seq: 1, state: %{count: 2}}, duplicate} =
             Counter.handle_event("inc", %{"_live_lift_seq" => 1}, next)

    assert duplicate.assigns.count == 2

    assert_raise ArgumentError, ~r/invalid LiveLift event sequence/, fn ->
      Counter.handle_event("inc", %{"_live_lift_seq" => "bad"}, next)
    end
  end

  test "reports an action gap and applies retries once in sequence order" do
    initial = %Phoenix.LiveView.Socket{assigns: %{count: 0, id: "counter", __changed__: %{}}}

    assert {:reply, %{expected_seq: 1, ack_seq: 0, revision: 0, state: %{count: 0}}, ^initial} =
             Counter.handle_event("inc", %{"_live_lift_seq" => 2}, initial)

    assert {:reply, %{ack_seq: 1, revision: 1, state: %{count: 1}}, first} =
             Counter.handle_event("inc", %{"_live_lift_seq" => 1}, initial)

    assert {:reply, %{ack_seq: 2, revision: 2, state: %{count: 2}}, second} =
             Counter.handle_event("inc", %{"_live_lift_seq" => 2}, first)

    assert {:reply, %{ack_seq: 2, revision: 2, state: %{count: 2}}, ^second} =
             Counter.handle_event("inc", %{"_live_lift_seq" => 2}, second)

    assert {:reply, %{ack_seq: 2, revision: 3, state: %{count: 3}}, unsequenced} =
             Counter.handle_event("inc", %{}, second)

    assert {:reply, %{ack_seq: 2, revision: 3, state: %{count: 3}}, ^unsequenced} =
             Counter.handle_event("inc", %{"_live_lift_seq" => 1}, unsequenced)
  end

  test "emits server event latency and outcome without parameter values" do
    handler_id = "live-lift-telemetry-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:live_lift, :component, :event],
        &__MODULE__.telemetry_handler/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    socket = %Phoenix.LiveView.Socket{assigns: %{count: 1, id: "counter", __changed__: %{}}}

    assert {:reply, _, next} = Counter.handle_event("inc", %{"_live_lift_seq" => 1}, socket)
    assert_receive {[:live_lift, :component, :event], %{duration: duration}, metadata}
    assert is_integer(duration) and duration >= 0

    assert metadata ==
             %{component: Counter, event: "inc", marked?: true, outcome: :ok}

    assert {:reply, _, _} = Counter.handle_event("inc", %{"_live_lift_seq" => 1}, next)
    assert_receive {_, _, %{outcome: :duplicate, marked?: true}}

    assert {:noreply, _} = Counter.handle_event("reset", %{}, next)
    assert_receive {_, _, %{event: "reset", marked?: false, outcome: :ok}}

    assert_raise ArgumentError, ~r/invalid LiveLift event sequence/, fn ->
      Counter.handle_event("inc", %{"_live_lift_seq" => "secret"}, socket)
    end

    assert_receive {_, _, %{event: "inc", marked?: true, outcome: :error}}
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

    assert {:reply, %{state: %{count: 2}}, _} =
             Counter.handle_event("inc", %{"profile" => %{"note" => "é"}}, socket)

    for params <- [
          %{"profile" => %{}},
          %{"profile" => %{"__proto__" => "x"}},
          %{"a" => %{"b" => %{"c" => %{"d" => %{"e" => "x"}}}}}
        ] do
      assert_raise ArgumentError, fn -> Counter.handle_event("inc", params, socket) end
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

  test "native map merge and delete keep server and browser results equal" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{item: %{label: "old", extra: "x"}, id: "map", __changed__: %{}}
    }

    assert {:reply, %{state: %{item: %{label: "new", extra: "x"}}}, _} =
             MapEditor.handle_event("merge", %{"label" => "new"}, socket)

    assert {:reply, %{state: %{item: %{label: "old"}}}, _} =
             MapEditor.handle_event("clear", %{}, socket)

    javascript = LiveLift.Client.Compiler.compile_module(MapEditor)
    path = Path.join(System.tmp_dir!(), "live_lift_map_#{System.unique_integer([:positive])}.mjs")

    try do
      File.write!(
        path,
        javascript <>
          "\nconst state = {item: {label: 'old', extra: 'x'}}; console.log(JSON.stringify([actions.merge(state, {params: {label: 'new'}}), actions.clear(state)]));"
      )

      {output, 0} = System.cmd("node", [path])

      assert Jason.decode!(output) == [
               %{"item" => %{"label" => "new", "extra" => "x"}},
               %{"item" => %{"label" => "old"}}
             ]
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

  test "unsupported marked timers report their source and suggest server execution" do
    for {args, params, callback, reason} <- [
          {"socket.assigns.myself, [value: 0], 60001", "_params", "", "literal delay"},
          {"socket.assigns.myself, [value: params[\"value\"]], 10", "params", "",
           "literal scalar"},
          {"socket.assigns.myself, [value: 0], 10", "%{}", "", "plain params argument"},
          {"socket.assigns.myself, [other: 0], 10", "_params", "", "used in the client"},
          {"socket.assigns.myself, [value: 0], 10", "_params",
           "def update(assigns, socket), do: {:ok, assign(socket, assigns)}", "default update"}
        ] do
      source = """
      defmodule LiveLift.ComponentTest.UnsupportedTimer do
        use Phoenix.LiveComponent
        use LiveLift
        def render(assigns), do: ~H"<output>{@value}</output>"
        @client true
        def handle_event("run", #{params}, socket) do
          Phoenix.LiveView.send_update_after(#{args})
          {:noreply, socket}
        end
        #{callback}
      end
      """

      assert_raise ArgumentError,
                   ~r/timer.ex:7: unsupported @client send_update_after\/3:.*#{reason}.*move it to a server handler/,
                   fn -> Code.compile_string(source, "timer.ex") end
    end
  end

  test "process timer rejections identify the scheduling source and native alternative" do
    for {behaviour, call, callback, reason} <- [
          {"LiveComponent", "self(), :tick, 0", "", "use send_update_after/3"},
          {"LiveView", "self(), {:tick, 1}, 0", "", "literal atom message"},
          {"LiveView", "self(), :tick, 0", "", "define an unguarded handle_info"},
          {"LiveView", "self(), :tick, 0",
           "def handle_info(_other, socket), do: {:noreply, socket}\n" <>
             "def handle_info(:tick, socket), do: {:noreply, assign(socket, :value, 1)}",
           "before any catch-all"}
        ] do
      source = """
      defmodule LiveLift.ComponentTest.UnsupportedProcessTimer do
        use Phoenix.#{behaviour}
        use LiveLift
        def render(assigns), do: ~H"<output>{@value}</output>"
        @client true
        def handle_event("run", _params, socket) do
          Process.send_after(#{call})
          {:noreply, socket}
        end
        #{callback}
      end
      """

      assert_raise ArgumentError,
                   ~r/process_timer.ex:7: unsupported @client Process.send_after\/3:.*#{reason}.*keep scheduling on the server/,
                   fn -> Code.compile_string(source, "process_timer.ex") end
    end
  end

  test "unpublished handler forms fail at their source before generating JavaScript" do
    expressions = [
      "Float.round(1.5, 1)",
      "cond do String.downcase(socket.assigns.value, :turkic) -> 1; true -> 0 end",
      "Enum.find(socket.assigns.items, fn item, _index -> item.keep end)",
      "Enum.reduce(socket.assigns.items, 0, fn item -> item end)",
      "Enum.sort_by(socket.assigns.items, fn item, _index -> item.id end)",
      "Enum.sort_by(socket.assigns.items, fn item -> item.id end, :desc)",
      "Enum.count(socket.assigns.items, fn item, _index -> item.keep end)",
      "Enum.join(socket.assigns.items, :separator)",
      "Enum.flat_map(socket.assigns.items, fn item, _index -> [item] end)",
      "String.downcase(socket.assigns.value, :turkic)",
      "String.split(socket.assigns.value, ~r/,/)",
      "String.replace(socket.assigns.value, ~r/a/, \"b\")",
      "Map.keys(socket.assigns.value)",
      "Map.values(socket.assigns.value)",
      "List.keydelete(socket.assigns.items, 1, 0)",
      "socket.assigns.items |> Enum.sum()"
    ]

    for {expression, index} <- Enum.with_index(expressions) do
      source = """
      defmodule LiveLift.ComponentTest.UnsupportedMatrix#{index} do
        use Phoenix.LiveComponent
        use LiveLift
        def render(assigns), do: ~H"<output>{@value}</output>"
        @client true
        def handle_event("run", _params, socket) do
          {:noreply, assign(socket, :value, #{expression})}
        end
      end
      """

      assert_raise ArgumentError,
                   ~r/matrix.ex:6: unsupported @client handler: unsupported client expression:.*move it to a server handler/s,
                   fn -> Code.compile_string(source, "matrix.ex") end
    end

    for {expression, index} <-
          Enum.with_index([
            "Enum.with_index(socket.assigns.items)",
            "Enum.with_index(socket.assigns.items, 1)"
          ]) do
      source = """
      defmodule LiveLift.ComponentTest.UnsupportedTupleIndex#{index} do
        use Phoenix.LiveComponent
        use LiveLift
        def render(assigns), do: ~H"<output>{@value}</output>"
        @client true
        def handle_event("run", _params, socket) do
          {:noreply, assign(socket, :value, #{expression})}
        end
      end
      """

      assert_raise ArgumentError,
                   ~r/matrix.ex:6: unsupported @client handler: unsupported client Enum.with_index tuple output; use Enum.with_index\(list, fn item, index ->/,
                   fn -> Code.compile_string(source, "matrix.ex") end
    end

    for {options, index} <- Enum.with_index(["parts: 0", "trim: :maybe", "unknown: true"]) do
      source = """
      defmodule LiveLift.ComponentTest.UnsupportedSplitOptions#{index} do
        use Phoenix.LiveComponent
        use LiveLift
        def render(assigns), do: ~H"<output>{@value}</output>"
        @client true
        def handle_event("run", _params, socket) do
          {:noreply, assign(socket, :value, String.split(socket.assigns.value, ",", #{options}))}
        end
      end
      """

      assert_raise ArgumentError,
                   ~r/matrix.ex:6: unsupported @client handler: unsupported client String.split\/3 options; use literal trim:/,
                   fn -> Code.compile_string(source, "matrix.ex") end
    end

    for {options, index} <-
          Enum.with_index(["global: :maybe", "insert_replaced: 0", "unknown: true"]) do
      source = """
      defmodule LiveLift.ComponentTest.UnsupportedReplaceOptions#{index} do
        use Phoenix.LiveComponent
        use LiveLift
        def render(assigns), do: ~H"<output>{@value}</output>"
        @client true
        def handle_event("run", _params, socket) do
          {:noreply, assign(socket, :value, String.replace(socket.assigns.value, "a", "b", #{options}))}
        end
      end
      """

      assert_raise ArgumentError,
                   ~r/matrix.ex:6: unsupported @client handler: unsupported client String.replace\/4 options; use literal global:/,
                   fn -> Code.compile_string(source, "matrix.ex") end
    end

    guarded_case = """
    defmodule LiveLift.ComponentTest.UnsupportedGuardedCase do
      use Phoenix.LiveComponent
      use LiveLift
      def render(assigns), do: ~H"<output>{@value}</output>"
      @client true
      def handle_event("run", _params, socket) do
        {:noreply, assign(socket, :value, case socket.assigns.value do other when is_integer(other) -> other; _ -> 0 end)}
      end
    end
    """

    assert_raise ArgumentError,
                 ~r/matrix.ex:6: unsupported @client handler: unsupported client case guard.*move it to a server handler/s,
                 fn -> Code.compile_string(guarded_case, "matrix.ex") end

    assign_new_source = """
    defmodule LiveLift.ComponentTest.UnsupportedAssignNew do
      use Phoenix.LiveComponent
      use LiveLift
      def render(assigns), do: ~H"<output>{@value}</output>"
      @client true
      def handle_event("run", _params, socket) do
        {:noreply, assign_new(socket, :value, fn _assigns -> 0 end)}
      end
    end
    """

    assert_raise ArgumentError,
                 ~r/matrix.ex:6: @client assign_new\/3 requires an atom key and a zero-argument function/,
                 fn -> Code.compile_string(assign_new_source, "matrix.ex") end
  end

  test "local client helpers reject guarded and recursive clauses with locations" do
    guarded = """
    defmodule LiveLift.ComponentTest.GuardedHelper do
      use Phoenix.LiveComponent
      use LiveLift
      def render(assigns), do: ~H"<output>{@value}</output>"
      @client true
      def handle_event("run", _params, socket) do
        {:noreply, assign(socket, :value, helper(socket.assigns.value))}
      end
      defp helper(value) when is_integer(value), do: value
    end
    """

    assert_raise ArgumentError,
                 ~r/helper.ex:9: client helper helper\/1 has a guard.*move this handler to the server/s,
                 fn -> Code.compile_string(guarded, "helper.ex") end

    recursive = """
    defmodule LiveLift.ComponentTest.RecursiveHelper do
      use Phoenix.LiveComponent
      use LiveLift
      def render(assigns), do: ~H"<output>{@value}</output>"
      @client true
      def handle_event("run", _params, socket) do
        {:noreply, assign(socket, :value, helper(socket.assigns.value))}
      end
      defp helper(value), do: helper(value)
    end
    """

    assert_raise ArgumentError,
                 ~r/helper.ex:6: recursive client helper helper\/1 is not supported.*move this handler to the server/s,
                 fn -> Code.compile_string(recursive, "helper.ex") end
  end

  test "local helper expansion has a source-located size bound" do
    definitions = [
      {:helper, [{:value, [], nil}], [], [do: 1], "helper.ex", 1}
    ]

    body = {:__block__, [], List.duplicate({:helper, [], [1]}, 1_001)}

    assert_raise ArgumentError, ~r/helper.ex:7: client helper expansion limit exceeded/, fn ->
      LiveLift.Component.Helpers.expand!(body, definitions, "helper.ex", 7)
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

  test "accepts bounded nested native form names and rejects invalid paths" do
    assert LiveLift.Template.compile_liveview(
             ~s(<form phx-submit="save"><input name="user[name]" /></form>),
             "form.ex",
             ["save"]
           )

    for name <- ["user[]", "user[name][]", "user[a][b][c][d]", "user[__proto__]"] do
      assert_raise ArgumentError, ~r/form.ex:1: @client form/, fn ->
        LiveLift.Template.compile_liveview(
          ~s(<form phx-submit="save"><input name="#{name}" /></form>),
          "form.ex",
          ["save"]
        )
      end
    end

    assert_raise ArgumentError, ~r/form.ex:1: @client form has conflicting map input names/, fn ->
      LiveLift.Template.compile_liveview(
        ~s(<form phx-submit="save"><input name="user" /><input name="user[name]" /></form>),
        "form.ex",
        ["save"]
      )
    end

    assert_raise ArgumentError,
                 ~r/direct.ex:1: @client direct phx-change requires a flat safe input name/,
                 fn ->
                   LiveLift.Template.compile_liveview(
                     ~s(<input name="profile[note]" phx-change="save" />),
                     "direct.ex",
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

  test "nested map pattern gives the same server and browser result" do
    source = """
    defmodule LiveLift.ComponentTest.NestedPattern do
      use Phoenix.LiveComponent
      use LiveLift
      def render(assigns), do: ~H'<form phx-submit="save"><input name="profile[note]" /><button>Save</button></form><p>{@saved}</p>'
      @client true
      def handle_event("save", %{"profile" => %{"note" => note}}, socket), do: {:noreply, assign(socket, :saved, note)}
    end
    """

    [{module, _}] = Code.compile_string(source, "nested_pattern.ex")
    socket = %Phoenix.LiveView.Socket{assigns: %{id: "nested", saved: "", __changed__: %{}}}

    assert {:reply, %{state: %{saved: "é <note>"}}, _} =
             module.handle_event("save", %{"profile" => %{"note" => "é <note>"}}, socket)

    script =
      Path.join(System.tmp_dir!(), "live_lift_nested_#{System.unique_integer([:positive])}.mjs")

    try do
      File.write!(
        script,
        LiveLift.Client.Compiler.compile_module(module) <>
          "\nconsole.log(JSON.stringify(actions.save({saved: ''}, {params: {profile: {note: 'é <note>'}}})));\n"
      )

      {output, 0} = System.cmd("node", [script])
      assert Jason.decode!(output) == %{"saved" => "é <note>"}
    after
      File.rm(script)
    end
  end

  test "app-defined local function component expands its props for the client" do
    tree = LocalBadge.__live_lift_client_template__()
    state = %{label: "<Ready>", visible: true}
    html = tree |> LiveLift.Template.render_server(state) |> Phoenix.HTML.safe_to_string()
    assert html =~ ~s(class="badge")
    assert html =~ ~s(class="card")
    assert html =~ ~s(title="Card")
    assert html =~ "&lt;Ready&gt;"
    assert html =~ "Ready"
    assert html =~ "A &amp; B"

    hidden =
      tree
      |> LiveLift.Template.render_server(%{state | visible: false})
      |> Phoenix.HTML.safe_to_string()

    refute hidden =~ "&lt;Ready&gt;"

    server = render_component(LocalBadge, id: "badge", label: "<Ready>", visible: true)
    assert server =~ "&lt;Ready&gt;"
    assert server =~ "Ready"
    assert server =~ "A &amp; B"

    socket = %Phoenix.LiveView.Socket{
      assigns: %{id: "badge", label: "<Ready>", visible: true, __changed__: %{}}
    }

    assert {:reply, %{state: %{visible: false}}, _} =
             LocalBadge.handle_event("toggle", %{}, socket)
  end

  test "local function component props work inside native keyed lists" do
    components = %{"badge" => %{source: "<span>{@label}</span>", file: "badge.ex"}}

    tree =
      LiveLift.Template.compile_liveview(
        ~s(<ul><li :for={item <- @items} id={item.id}><.badge label={item.label} /></li></ul>),
        "list.ex",
        [],
        components
      )

    html =
      tree
      |> LiveLift.Template.render_server(%{items: [%{id: "a", label: "<A>"}]})
      |> Phoenix.HTML.safe_to_string()

    assert html =~ ~s(data-live-lift-key="a")
    assert html =~ "&lt;A&gt;"
  end

  test "local function component errors point to unsupported calls and props" do
    components = %{"badge" => %{source: "<span>{@label}</span>", file: "badge.ex"}}

    assert_raise ArgumentError,
                 ~r/missing.ex:1: unknown client function component .missing/,
                 fn ->
                   LiveLift.Template.compile_liveview(
                     "<.missing />",
                     "missing.ex",
                     [],
                     components
                   )
                 end

    assert_raise ArgumentError, ~r/call.ex:1: missing function component prop label/, fn ->
      LiveLift.Template.compile_liveview("<.badge />", "call.ex", [], components)
    end

    assert_raise ArgumentError,
                 ~r/call.ex:1: client function component .badge does not render its default slot/,
                 fn ->
                   LiveLift.Template.compile_liveview(
                     "<.badge>child</.badge>",
                     "call.ex",
                     [],
                     components
                   )
                 end

    assert_raise ArgumentError,
                 ~r/call.ex:1: client function component supports named props only/,
                 fn ->
                   LiveLift.Template.compile_liveview(
                     "<.badge :if={@show} />",
                     "call.ex",
                     [],
                     components
                   )
                 end

    assert_raise ArgumentError, ~r/encoded function component prop label is not supported/, fn ->
      LiveLift.Template.compile_liveview(
        ~s(<.badge label="A &amp; B" />),
        "call.ex",
        [],
        components
      )
    end

    assert_raise ArgumentError, ~r/slot header is not supported/, fn ->
      LiveLift.Template.compile_liveview(
        "<.badge><:header>Header</:header></.badge>",
        "call.ex",
        [],
        components
      )
    end

    assert_raise ArgumentError, ~r/may render its default slot once/, fn ->
      LiveLift.Template.compile_liveview(
        "<.card>content</.card>",
        "call.ex",
        [],
        %{
          "card" => %{
            source: "<div>{render_slot(@inner_block)}{render_slot(@inner_block)}</div>",
            file: "card.ex",
            line: 1
          }
        }
      )
    end

    assert_raise ArgumentError, ~r/recursive client function component/, fn ->
      LiveLift.Template.compile_liveview(
        "<.badge />",
        "call.ex",
        [],
        %{"badge" => %{source: "<.badge />", file: "badge.ex"}}
      )
    end

    assert_raise ArgumentError, ~r/remote function component/, fn ->
      LiveLift.Template.compile_liveview("<Other.Badge />", "call.ex", [], components)
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
