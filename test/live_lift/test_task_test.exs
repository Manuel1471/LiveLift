defmodule LiveLift.TestTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Phoenix.LiveViewTest, only: [render_component: 2]

  defmodule Counter do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<button phx-click='inc' phx-target={@myself}>{@count}</button>"

    @client true
    def handle_event("inc", %{"step" => step}, socket) do
      {:noreply, update(socket, :count, &(&1 + String.length(step)))}
    end
  end

  defmodule Nested do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<output>{@item.label}</output>"

    @client true
    def handle_event("label", params, socket) do
      {:noreply, update(socket, :item, &Map.put(&1, :label, params["label"]))}
    end
  end

  defmodule Drift do
    def __live_lift_client_actions__,
      do: [
        {:inc, :state, quote(do: %{count: state.count + 1})},
        {:typed, :state, quote(do: state)}
      ]

    def __live_lift_component_fields__, do: [:count]
    def __live_lift_client_template__, do: []

    def handle_event("inc", _params, socket),
      do: {:reply, %{state: %{count: socket.assigns.count}}, socket}

    def handle_event("typed", _params, socket),
      do: {:reply, %{state: %{count: socket.assigns.count / 1}}, socket}
  end

  defmodule MissingTimer do
    def __live_lift_client_actions__, do: [{:preview, :state, quote(do: state)}]
    def __live_lift_component_fields__, do: [:count]
    def __live_lift_client_template__, do: []
    def __live_lift_component_timers__, do: %{"preview" => %{delay: 10, patch: %{count: 1}}}

    def handle_event("preview", _params, socket),
      do: {:reply, %{state: %{count: socket.assigns.count}}, socket}

    def update(patch, socket), do: {:ok, Phoenix.Component.assign(socket, patch)}
  end

  defmodule Multi do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<output>{@count}</output>"

    @client true
    def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}

    @client true
    def handle_event("dec", _params, socket), do: {:noreply, update(socket, :count, &(&1 - 1))}
  end

  defmodule FloatCounter do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<output>{@value}</output>"

    @client true
    def handle_event("inc", _params, socket),
      do: {:noreply, update(socket, :value, &(&1 + 0.5))}
  end

  defmodule HelperCounter do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<output>{@label}</output>"

    @client true
    def handle_event("classify", _params, socket),
      do: {:noreply, assign(socket, :label, classify(socket.assigns.value))}

    defp classify(nil), do: "empty"
    defp classify(%{id: id}), do: Integer.to_string(id)
    defp classify([head | _tail]), do: Integer.to_string(head)
    defp classify(_other), do: "other"
  end

  defmodule NestedHelperCounter do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<output>{@label}</output>"

    @client true
    def handle_event("label", _params, socket),
      do: {:noreply, assign(socket, :label, format_value(socket.assigns.value, "!"))}

    defp format_value(nil, suffix), do: "none" <> suffix
    defp format_value(value, suffix), do: Integer.to_string(value) <> decorate(suffix)
    defp decorate(value), do: value <> value
  end

  defmodule SparseHelper do
    use Phoenix.LiveComponent
    use LiveLift

    def render(assigns), do: ~H"<output>{@label}</output>"

    @client true
    def handle_event("label", _params, socket),
      do: {:noreply, assign(socket, :label, label(socket.assigns.value))}

    defp label(1), do: "one"
    defp label(2), do: "two"
  end

  test "a local helper with no matching clause fails on both sides" do
    socket = %Phoenix.LiveView.Socket{assigns: %{label: "", value: 3, __changed__: %{}}}

    assert_raise FunctionClauseError, fn ->
      SparseHelper.handle_event("label", %{"_live_lift_seq" => 1}, socket)
    end

    source =
      LiveLift.Client.Compiler.compile_module(SparseHelper) <>
        "\nactions.label({label: '', value: 3});\n"

    path =
      Path.join(System.tmp_dir!(), "live_lift_sparse_#{System.unique_integer([:positive])}.mjs")

    try do
      File.write!(path, source)
      {output, status} = System.cmd("node", [path], stderr_to_stdout: true)
      assert status != 0
      assert output =~ "LiveLift helper has no matching clause: label/1"
    after
      File.rm(path)
    end
  end

  test "expands multi-argument clauses and local helper calls in later definitions" do
    for {value, expected} <- [{nil, "none!"}, {3, "3!!"}] do
      socket = %Phoenix.LiveView.Socket{assigns: %{label: "", value: value, __changed__: %{}}}

      assert {:reply, %{state: %{label: ^expected}}, _} =
               NestedHelperCounter.handle_event("label", %{"_live_lift_seq" => 1}, socket)

      state = %{label: "", value: value} |> Jason.encode!()

      output =
        capture_io(fn ->
          Mix.Tasks.LiveLift.Test.run([
            "LiveLift.TestTaskTest.NestedHelperCounter",
            "--event",
            "label",
            "--state",
            state
          ])
        end)

      assert output =~
               ~s|Parity passed: LiveLift.TestTaskTest.NestedHelperCounter.handle_event("label")|
    end
  end

  test "compares a marked handler using a later multi-clause defp" do
    for value <- [nil, %{id: 7, extra: true}, [3, 4], "hello"] do
      state = %{label: "", value: value} |> Jason.encode!()

      output =
        capture_io(fn ->
          Mix.Tasks.LiveLift.Test.run([
            "LiveLift.TestTaskTest.HelperCounter",
            "--event",
            "classify",
            "--state",
            state
          ])
        end)

      assert output =~
               ~s|Parity passed: LiveLift.TestTaskTest.HelperCounter.handle_event("classify")|
    end
  end

  test "compares a native float handler using the tagged wire value" do
    html = render_component(&FloatCounter.render/1, id: "float-counter", value: -0.0)

    assert html =~ "<!--live-lift:text-->-0.0<!--live-lift:end-->" or html =~ ">-0.0</output>"
    assert html =~ "$live_lift_float"

    output =
      capture_io(fn ->
        Mix.Tasks.LiveLift.Test.run([
          "LiveLift.TestTaskTest.FloatCounter",
          "--event",
          "inc",
          "--state",
          ~s({"value":{"$live_lift_float":"1.5"}})
        ])
      end)

    assert output =~ ~s|Parity passed: LiveLift.TestTaskTest.FloatCounter.handle_event("inc")|
  end

  test "compares a marked handler in Elixir and Node" do
    output =
      capture_io(fn ->
        Mix.Tasks.LiveLift.Test.run([
          "LiveLift.TestTaskTest.Counter",
          "--event",
          "inc",
          "--state",
          ~s({"count":1}),
          "--params",
          ~s({"step":"é"})
        ])
      end)

    assert output =~ ~s|Parity passed: LiveLift.TestTaskTest.Counter.handle_event("inc")|
  end

  test "restores safe nested atom keys for the original Elixir handler" do
    output =
      capture_io(fn ->
        Mix.Tasks.LiveLift.Test.run([
          "LiveLift.TestTaskTest.Nested",
          "--event",
          "label",
          "--state",
          ~s({"item":{"label":"old"}}),
          "--params",
          ~s({"label":"new"})
        ])
      end)

    assert output =~ ~s|Parity passed: LiveLift.TestTaskTest.Nested.handle_event("label")|
  end

  test "rejects missing fields and unmarked events" do
    assert_raise Mix.Error, ~r/state keys must be exactly: count/, fn ->
      Mix.Tasks.LiveLift.Test.run([
        "LiveLift.TestTaskTest.Counter",
        "--event",
        "inc",
        "--state",
        "{}"
      ])
    end

    assert_raise Mix.Error, ~r/has no marked @client event/, fn ->
      Mix.Tasks.LiveLift.Test.run([
        "LiveLift.TestTaskTest.Counter",
        "--event",
        "save",
        "--state",
        ~s({"count":1})
      ])
    end
  end

  test "reports a real mismatch between the server and generated action" do
    assert_raise Mix.Error, ~r/Elixir\/JavaScript mismatch/, fn ->
      Mix.Tasks.LiveLift.Test.run([
        "LiveLift.TestTaskTest.Drift",
        "--event",
        "inc",
        "--state",
        ~s({"count":0})
      ])
    end
  end

  test "fails if equal-looking JSON numbers have different wire types" do
    assert_raise Mix.Error, ~r/Elixir\/JavaScript mismatch.*typed/, fn ->
      Mix.Tasks.LiveLift.Test.run([
        "LiveLift.TestTaskTest.Drift",
        "--event",
        "typed",
        "--state",
        ~s({"count":1})
      ])
    end
  end

  test "fails when a declared timer never enters the authoritative queue" do
    assert_raise Mix.Error, ~r/did not schedule exactly one LiveLift timer/, fn ->
      Mix.Tasks.LiveLift.Test.run([
        "LiveLift.TestTaskTest.MissingTimer",
        "--event",
        "preview",
        "--state",
        ~s({"count":0})
      ])
    end
  end

  test "a cases file runs every event in listed modules" do
    path =
      Path.join(System.tmp_dir!(), "live_lift_cases_#{System.unique_integer([:positive])}.json")

    cases = [
      %{module: "LiveLift.TestTaskTest.Multi", event: "inc", state: %{count: 0}},
      %{module: "LiveLift.TestTaskTest.Multi", event: "dec", state: %{count: 0}},
      %{
        module: "LiveLift.TestTaskTest.Counter",
        event: "inc",
        state: %{count: 1},
        params: %{step: "é"}
      }
    ]

    try do
      File.write!(path, Jason.encode!(cases))
      output = capture_io(fn -> Mix.Tasks.LiveLift.Test.run(["--cases", path]) end)
      assert output =~ "3 parity cases passed across 2 modules"

      File.write!(path, Jason.encode!(Enum.take(cases, 1)))

      assert_raise Mix.Error, ~r/marked events without cases: dec/, fn ->
        capture_io(fn -> Mix.Tasks.LiveLift.Test.run(["--cases", path]) end)
      end
    after
      File.rm(path)
    end
  end
end
