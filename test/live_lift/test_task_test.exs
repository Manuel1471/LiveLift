defmodule LiveLift.TestTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

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
      do: [{:inc, :state, quote(do: %{count: state.count + 1})}]

    def __live_lift_component_fields__, do: [:count]
    def __live_lift_client_template__, do: []

    def handle_event("inc", _params, socket),
      do: {:reply, %{state: %{count: socket.assigns.count}}, socket}
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
