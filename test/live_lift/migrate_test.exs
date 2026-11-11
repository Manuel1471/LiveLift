defmodule LiveLift.MigrateTest do
  use ExUnit.Case, async: false

  test "converts a one-field legacy click into a compilable native component" do
    root = temp_root()
    source = Path.join(root, "legacy.ex")
    target = Path.join(root, "counter.ex")
    module = "MigratedCounter#{System.unique_integer([:positive])}"

    File.write!(source, """
    defmodule LegacyCounter do
      use LiveLift.Client
      client_template("<button type='button' $click='inc'>Add</button><output>{@count}</output>")
      defclient inc(state), do: %{state | count: state.count + 1}
    end
    """)

    try do
      Mix.Tasks.LiveLift.Migrate.run([source, "--module", module, "--output", target])
      output = File.read!(target)
      assert output =~ "use Phoenix.LiveComponent"
      assert output =~ "phx-click=\"inc\" phx-target={@myself}"
      assert output =~ "@client true"
      assert output =~ "socket.assigns.count + 1"

      [{compiled, _}] = Code.compile_file(target)
      assert inspect(compiled) == module
      assert compiled.__live_lift_client_actions__() != []
    after
      File.rm_rf!(root)
    end
  end

  test "rejects a legacy server event without writing a partial component" do
    root = temp_root()
    source = Path.join(root, "legacy.ex")
    target = Path.join(root, "counter.ex")

    File.write!(source, """
    defmodule LegacyCounter do
      use LiveLift.Client
      client_template("<button $server='save'>Save</button>")
      defclient inc(state), do: %{state | count: state.count + 1}
    end
    """)

    try do
      assert_raise Mix.Error, ~r/legacy\.ex:\d+: \$server needs manual migration/, fn ->
        Mix.Tasks.LiveLift.Migrate.run([
          source,
          "--module",
          "MigratedCounter",
          "--output",
          target
        ])
      end

      refute File.exists?(target)
    after
      File.rm_rf!(root)
    end
  end

  test "multiple legacy fields read the same original state on server and client" do
    root = temp_root()
    source = Path.join(root, "legacy.ex")
    target = Path.join(root, "counter.ex")
    script = Path.join(root, "action.mjs")
    module = "MigratedFields#{System.unique_integer([:positive])}"

    File.write!(source, """
    defmodule LegacyFields do
      use LiveLift.Client
      client_template("<button $click='advance'>Go</button><output>{@count} {@previous}</output>")
      defclient advance(state), do: %{state | count: state.count + 1, previous: state.count}
    end
    """)

    try do
      Mix.Tasks.LiveLift.Migrate.run([source, "--module", module, "--output", target])
      [{compiled, _}] = Code.compile_file(target)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{id: "migrated", count: 4, previous: 0, __changed__: %{}}
      }

      assert {:reply, %{state: %{count: 5, previous: 4}}, _} =
               compiled.handle_event("advance", %{}, socket)

      javascript = LiveLift.Client.Compiler.compile_module(compiled)

      File.write!(
        script,
        javascript <> "\nconsole.log(JSON.stringify(actions.advance({count: 4, previous: 0})));\n"
      )

      {output, 0} = System.cmd("node", [script])
      assert Jason.decode!(output) == %{"count" => 5, "previous" => 4}
    after
      File.rm_rf!(root)
    end
  end

  test "migrates a text input event with flat value params" do
    root = temp_root()
    source = Path.join(root, "legacy.ex")
    target = Path.join(root, "draft.ex")
    script = Path.join(root, "draft.mjs")
    module = "MigratedDraft#{System.unique_integer([:positive])}"

    File.write!(source, """
    defmodule LegacyDraft do
      use LiveLift.Client
      client_template("<input type='text' value='{@draft}' $input='set_draft' /><output>{@draft}</output>")
      defclient set_draft(state, event), do: %{state | draft: event.value}
    end
    """)

    try do
      Mix.Tasks.LiveLift.Migrate.run([source, "--module", module, "--output", target])
      output = File.read!(target)
      assert output =~ "phx-change=\"set_draft\""
      assert output =~ "name=\"value\" phx-target={@myself}"

      [{compiled, _}] = Code.compile_file(target)
      socket = %Phoenix.LiveView.Socket{assigns: %{id: "draft", draft: "", __changed__: %{}}}

      assert {:reply, %{state: %{draft: "Hi"}}, _} =
               compiled.handle_event("set_draft", %{"value" => "Hi"}, socket)

      File.write!(
        script,
        LiveLift.Client.Compiler.compile_module(compiled) <>
          "\nconsole.log(JSON.stringify(actions.set_draft({draft: ''}, {params: {value: 'Hi'}})));\n"
      )

      {result, 0} = System.cmd("node", [script])
      assert Jason.decode!(result) == %{"draft" => "Hi"}
    after
      File.rm_rf!(root)
    end
  end

  test "migrates select changes and textarea input with browser parity" do
    root = temp_root()
    source = Path.join(root, "legacy.ex")
    target = Path.join(root, "form.ex")
    script = Path.join(root, "form.mjs")
    module = "MigratedForm#{System.unique_integer([:positive])}"

    File.write!(source, """
    defmodule LegacyForm do
      use LiveLift.Client
      client_template("<select $change='choose'><option value='a' selected={@first}>A</option><option value='b' selected={@second}>B</option></select><textarea $input='edit'>{@note}</textarea>")
      defclient choose(state, event), do: %{state | first: event.value == "a", second: event.value == "b"}
      defclient edit(state, event), do: %{state | note: event.value}
    end
    """)

    try do
      Mix.Tasks.LiveLift.Migrate.run([source, "--module", module, "--output", target])
      output = File.read!(target)
      assert output =~ "phx-change=\"choose\""
      assert output =~ "phx-change=\"edit\""
      assert output =~ "selected={@first}"

      [{compiled, _}] = Code.compile_file(target)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{id: "form", first: true, second: false, note: "A", __changed__: %{}}
      }

      assert {:reply, %{state: %{first: false, second: true, note: "A"}}, _} =
               compiled.handle_event("choose", %{"value" => "b"}, socket)

      File.write!(
        script,
        LiveLift.Client.Compiler.compile_module(compiled) <>
          "\nconsole.log(JSON.stringify({choose: actions.choose({first: true, second: false, note: 'A'}, {params: {value: 'b'}}), edit: actions.edit({first: true, second: false, note: 'A'}, {params: {value: 'B'}})}));\n"
      )

      {result, 0} = System.cmd("node", [script])

      assert Jason.decode!(result) == %{
               "choose" => %{"first" => false, "second" => true, "note" => "A"},
               "edit" => %{"first" => true, "second" => false, "note" => "B"}
             }
    after
      File.rm_rf!(root)
    end
  end

  defp temp_root do
    root = Path.join(System.tmp_dir!(), "live_lift_migrate_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    root
  end
end
