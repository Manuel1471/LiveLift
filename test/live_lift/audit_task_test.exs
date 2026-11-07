defmodule LiveLift.AuditTaskTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "reports compatible and blocked handlers without changing source" do
    directory =
      Path.join(System.tmp_dir!(), "live_lift_audit_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    file = Path.join(directory, "counter.ex")

    source = """
    defmodule Demo.Counter do
      use Phoenix.LiveComponent

      def render(assigns), do: ~H"<button phx-click='inc'>{@count}</button>"

      def handle_event("inc", _params, socket) do
        {:noreply, update(socket, :count, &(&1 + 1))}
      end

      def handle_event("save", _params, socket) do
        {:noreply, send(self(), socket)}
      end
    end
    """

    try do
      File.write!(file, source)
      output = capture_io(fn -> Mix.Tasks.LiveLift.Audit.run(["--path", file]) end)

      assert output =~ ~s|Demo.Counter.handle_event("inc"): compatible|
      assert output =~ ~s|Demo.Counter.handle_event("save"): blocked:|
      assert output =~ "1/2 handlers compatible"
      assert File.read!(file) == source
    after
      File.rm_rf!(directory)
    end
  end

  test "recognizes Phoenix's usual live_component use form" do
    directory =
      Path.join(System.tmp_dir!(), "live_lift_audit_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    file = Path.join(directory, "component.ex")

    try do
      File.write!(
        file,
        """
        defmodule Demo.Component do
          use DemoWeb, :live_component
          def render(assigns), do: ~H"<output>{@count}</output>"
          def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
        end
        """
      )

      output = capture_io(fn -> Mix.Tasks.LiveLift.Audit.run(["--path", directory]) end)
      assert output =~ ~s|Demo.Component.handle_event("inc"): compatible|
    after
      File.rm_rf!(directory)
    end
  end

  test "reports the actual render line for unsafe templates" do
    directory =
      Path.join(System.tmp_dir!(), "live_lift_audit_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    file = Path.join(directory, "unsafe.ex")

    try do
      File.write!(
        file,
        """
        defmodule Demo.Unsafe do
          use Phoenix.LiveComponent
          def render(assigns), do: ~H"<a href='javascript:alert(1)'>{@count}</a>"
          def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
        end
        """
      )

      output = capture_io(fn -> Mix.Tasks.LiveLift.Audit.run(["--path", file]) end)
      assert output =~ "#{file}:3: unsafe client attribute: href"
      assert output =~ "0/1 handlers compatible"
    after
      File.rm_rf!(directory)
    end
  end

  test "does not mark duplicate event clauses as compatible" do
    directory =
      Path.join(System.tmp_dir!(), "live_lift_audit_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    file = Path.join(directory, "duplicate.ex")

    try do
      File.write!(
        file,
        """
        defmodule Demo.Duplicate do
          use Phoenix.LiveComponent
          def render(assigns), do: ~H"<output>{@count}</output>"
          def handle_event("inc", %{"step" => 1}, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
          def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 2))}
        end
        """
      )

      output = capture_io(fn -> Mix.Tasks.LiveLift.Audit.run(["--path", file]) end)
      assert output =~ "multiple clauses for this event"
      assert output =~ "0/2 handlers compatible"
    after
      File.rm_rf!(directory)
    end
  end
end
