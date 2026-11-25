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
      assert output =~ "#{file}:11: @client supports assign/3, literal assign/2 and update/3"
      assert output =~ "(E055)"
      assert output =~ "docs/errors/E055.md"
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

  test "recognizes local multi-clause helpers declared after a handler" do
    directory =
      Path.join(System.tmp_dir!(), "live_lift_audit_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    file = Path.join(directory, "helper.ex")

    try do
      File.write!(
        file,
        """
        defmodule Demo.Helper do
          use Phoenix.LiveComponent
          def render(assigns), do: ~H"<output>{@label}</output>"
          def handle_event("label", _params, socket), do: {:noreply, assign(socket, :label, socket.assigns.value |> label())}
          defp label(nil), do: "empty"
          defp label(value), do: Integer.to_string(value)
        end
        """
      )

      output = capture_io(fn -> Mix.Tasks.LiveLift.Audit.run(["--path", file]) end)
      assert output =~ ~s|Demo.Helper.handle_event("label"): compatible|
      assert output =~ "1/1 handlers compatible"
    after
      File.rm_rf!(directory)
    end
  end

  test "audits the colocated HEEx file only without an explicit render" do
    directory = tmp_dir!()
    file = Path.join(directory, "co_located.ex")
    template = Path.join(directory, "co_located.html.heex")

    source = """
    defmodule Demo.CoLocated do
      use Phoenix.LiveView
      def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
    end
    """

    File.write!(file, source)
    File.write!(template, "\n<output>{@count}</output>\n")
    audit = fn -> capture_io(fn -> Mix.Tasks.LiveLift.Audit.run(["--path", file]) end) end

    assert audit.() =~ ~s|Demo.CoLocated.handle_event("inc"): compatible|

    File.write!(template, "\n<output data-custom={@count}>{@count}</output>\n")
    assert audit.() =~ ~r/blocked: #{Regex.escape(template)}:2(?::\d+)?:.*\(E061\)/

    File.write!(
      file,
      String.replace(
        source,
        "  def handle_event",
        "  def render(assigns), do: Other.render(assigns)\n  def handle_event"
      )
    )

    assert audit.() =~ "blocked: #{file}:3: render/1 must return a literal ~H template (E060)"
  end

  test "audits nested local HEEx functions and slots like the native compiler" do
    file = Path.join(tmp_dir!(), "card.ex")

    source = ~S'''
    defmodule Demo.AuditedCard do
      use Phoenix.LiveComponent

      def render(assigns) do
        ~H"<.card title={@title}><strong>{@title}</strong></.card>"
      end

      defp card(assigns) do
        ~H"""
        <section>
          <.heading title={@title} />
          {render_slot(@inner_block)}
        </section>
        """
      end

      def heading(assigns), do: ~H"<h2>{@title}</h2>"

      def handle_event("clear", _params, socket),
        do: {:noreply, assign(socket, :title, "")}
    end
    '''

    File.write!(file, source)
    audit = fn -> capture_io(fn -> Mix.Tasks.LiveLift.Audit.run(["--path", file]) end) end
    assert audit.() =~ ~s|Demo.AuditedCard.handle_event("clear"): compatible|
    assert File.read!(file) == source

    opted_in =
      source
      |> String.replace(
        "  use Phoenix.LiveComponent",
        "  use Phoenix.LiveComponent\n  use LiveLift"
      )
      |> String.replace("  def handle_event", "  @client true\n  def handle_event")

    [{module, _binary}] = Code.compile_string(opted_in, file)
    assert module.__live_lift_component_fields__() == [:title]

    File.write!(file, String.replace(source, "<.heading", "<.external_heading"))

    assert audit.() =~
             ~r/card\.ex:11:.*unknown client function component \.external_heading.*\(E062\)/

    File.write!(
      file,
      String.replace(
        source,
        "  def handle_event",
        "  def heading(_assigns), do: ~H\"<p />\"\n  def handle_event"
      )
    )

    assert audit.() =~
             ~r/card\.ex:19:.*client function component \.heading has multiple clauses.*\(E062\)/
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

  test "audits component and mailbox timers without evaluating their source" do
    directory = tmp_dir!()
    file = Path.join(directory, "timers.ex")

    source = """
    defmodule Demo.ComponentTimer do
      use Phoenix.LiveComponent
      alias Phoenix.LiveView, as: LV
      raise "audit evaluated the module"
      def render(assigns), do: ~H"<output>{@label}</output>"
      def handle_event("preview", _params, socket) do
        LV.send_update_after(socket.assigns.myself, [label: "Ready"], 50)
        {:noreply, socket}
      end
      def handle_event("missing", _params, socket) do
        LV.send_update_after(socket.assigns.myself, [unused: "Ready"], 50)
        {:noreply, socket}
      end
      def handle_event("delay", _params, socket) do
        LV.send_update_after(socket.assigns.myself, [label: "Ready"], 60_001)
        {:noreply, socket}
      end
      def handle_event("mailbox", _params, socket) do
        Process.send_after(self(), :ready, 50)
        {:noreply, socket}
      end
    end

    defmodule Demo.ViewTimer do
      use DemoWeb, :live_view
      alias Process, as: Mailbox
      def render(assigns), do: ~H"<output>{@count}</output>"
      def handle_event("preview", _params, socket) do
        Mailbox.send_after(self(), :ready, 50)
        {:noreply, socket}
      end
      def handle_event("missing", _params, socket) do
        Mailbox.send_after(self(), :missing, 50)
        {:noreply, socket}
      end
      def handle_event("guarded", _params, socket) do
        Mailbox.send_after(self(), :guarded, 50)
        {:noreply, socket}
      end
      def handle_event("component", _params, socket) do
        Phoenix.LiveView.send_update_after(socket.assigns.myself, [count: 1], 50)
        {:noreply, socket}
      end
      def handle_info(:ready, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
      def handle_info(:guarded, socket) when is_map(socket), do: {:noreply, socket}
    end

    defmodule Demo.ShadowedSelf do
      use Phoenix.LiveView
      import Kernel, except: [self: 0]
      def render(assigns), do: ~H"<output>{@count}</output>"
      defp self(), do: Kernel.self()
      def handle_event("preview", _params, socket) do
        Process.send_after(self(), :ready, 50)
        {:noreply, socket}
      end
      def handle_info(:ready, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
    end
    """

    File.write!(file, source)
    output = capture_io(fn -> Mix.Tasks.LiveLift.Audit.run(["--path", file]) end)
    assert output =~ ~s|Demo.ComponentTimer.handle_event("preview"): compatible|
    assert output =~ ~s|Demo.ViewTimer.handle_event("preview"): compatible|
    assert output =~ "#{file}:11: unsupported @client send_update_after/3: assign only fields"
    assert output =~ "literal delay from 0 to 60000 ms"
    assert output =~ "the LiveView owns the mailbox"
    assert output =~ "define an unguarded handle_info(:missing, socket)"
    assert output =~ "define an unguarded handle_info(:guarded, socket)"
    assert output =~ "use Process.send_after/3 to schedule a callback on the LiveView itself"
    assert output =~ "use a plain params argument, self(), a literal atom message"
    assert output =~ "2/9 handlers compatible"
    assert File.read!(file) == source
  end

  test "audits custom updates and mailbox callback order" do
    file = Path.join(tmp_dir!(), "timers.ex")

    File.write!(
      file,
      """
      defmodule Demo.CustomUpdate do
        use DemoWeb, :live_component
        def render(assigns), do: ~H"<output>{@label}</output>"
        def update_many(entries), do: entries
        def handle_event("preview", _params, socket) do
          Phoenix.LiveView.send_update_after(socket.assigns.myself, [label: "Ready"], 50)
          {:noreply, socket}
        end
      end

      defmodule Demo.CatchAll do
        use Phoenix.LiveView
        def render(assigns), do: ~H"<output>{@label}</output>"
        def handle_info(_, socket), do: {:noreply, socket}
        def handle_info(:ready, socket), do: {:noreply, assign(socket, :label, "Ready")}
        def handle_event("preview", _params, socket) do
          Process.send_after(self(), :ready, 50)
          {:noreply, socket}
        end
      end
      """
    )

    output = capture_io(fn -> Mix.Tasks.LiveLift.Audit.run(["--path", file]) end)
    assert output =~ "the component must use Phoenix's default update callback"
    assert output =~ "define an unguarded handle_info(:ready, socket) clause before any catch-all"
    assert output =~ "0/2 handlers compatible"
  end

  defp tmp_dir! do
    dir = Path.join(System.tmp_dir!(), "live_lift_audit_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
