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

    File.write!(Path.join(root, ".gitignore"), "/_build/\n")

    try do
      File.cd!(root, fn ->
        Mix.Tasks.LiveLift.Install.run([])
        first = {File.read!("assets/js/app.js"), File.read!("mix.exs"), File.read!(".gitignore")}
        Mix.Tasks.LiveLift.Install.run([])

        assert first ==
                 {File.read!("assets/js/app.js"), File.read!("mix.exs"), File.read!(".gitignore")}

        assert elem(first, 0) =~ "LiveLift: createClientHook(liveLiftViews)"

        assert String.split(
                 elem(first, 1),
                 "live_lift.compile --output assets/js/generated_views.js"
               )
               |> length() == 3

        assert elem(first, 2) =~ "/assets/js/generated_views.js.map"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "repairs an alias left out of a partial installation" do
    root = temp_root()

    js = """
    import {createClientHook} from "./live_lift_runtime.js"
    import {views as liveLiftViews} from "./generated_views.js"
    import {hooks as colocatedHooks} from "phoenix-colocated/my_app"
    const liveSocket = new LiveSocket("/live", Socket, {hooks: {...colocatedHooks, LiveLift: createClientHook(liveLiftViews)}})
    """

    mix = """
    "assets.build": ["compile", "live_lift.compile --output assets/js/generated_views.js", "esbuild my_app"],
    "assets.deploy": ["esbuild my_app --minify"]
    """

    File.write!(Path.join(root, "assets/js/app.js"), js)
    File.write!(Path.join(root, "mix.exs"), mix)

    try do
      File.cd!(root, fn ->
        Mix.Tasks.LiveLift.Install.run([])
        assert File.read!("assets/js/app.js") == js

        installed = File.read!("mix.exs")

        assert String.split(installed, "live_lift.compile --output assets/js/generated_views.js")
               |> length() == 3
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "unsupported hook layout leaves every file untouched" do
    root = temp_root()
    js = "const liveSocket = new LiveSocket(\"/live\", Socket, {hooks: {...colocatedHooks}})\n"

    mix = """
    "assets.build": ["compile", "esbuild my_app"],
    "assets.deploy": ["esbuild my_app --minify"]
    """

    File.write!(Path.join(root, "assets/js/app.js"), js)
    File.write!(Path.join(root, "mix.exs"), mix)

    try do
      File.cd!(root, fn ->
        assert_raise Mix.Error, ~r/expected the Phoenix colocatedHooks import/, fn ->
          Mix.Tasks.LiveLift.Install.run([])
        end

        assert File.read!("assets/js/app.js") == js
        assert File.read!("mix.exs") == mix
      end)
    after
      File.rm_rf!(root)
    end
  end

  defp temp_root do
    root = Path.join(System.tmp_dir!(), "live_lift_install_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "assets/js"))
    root
  end
end
