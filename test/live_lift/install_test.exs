defmodule LiveLift.InstallTest do
  use ExUnit.Case, async: false

  test "installer wires standard Phoenix assets once" do
    root = Path.join(System.tmp_dir!(), "live_lift_install_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "assets/js"))

    File.write!(Path.join(root, "assets/js/app.js"), """
    import {hooks as colocatedHooks} from "phoenix-colocated/my_app"
    const liveSocket = new LiveSocket("/live", Socket, {hooks: {...colocatedHooks}})
    """)

    File.write!(Path.join(root, "mix.exs"), """
    "assets.build": ["compile", "esbuild my_app"],
    "assets.deploy": ["esbuild my_app --minify"]
    """)

    try do
      File.cd!(root, fn ->
        Mix.Tasks.LiveLift.Install.run([])
        first = {File.read!("assets/js/app.js"), File.read!("mix.exs")}
        Mix.Tasks.LiveLift.Install.run([])
        assert first == {File.read!("assets/js/app.js"), File.read!("mix.exs")}
        assert elem(first, 0) =~ "LiveLift: createClientHook(liveLiftViews)"
        assert elem(first, 1) =~ "live_lift.compile --output assets/js/generated_views.js"
      end)
    after
      File.rm_rf!(root)
    end
  end
end
