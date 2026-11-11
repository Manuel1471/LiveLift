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

  defp temp_root do
    root = Path.join(System.tmp_dir!(), "live_lift_migrate_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    root
  end
end
