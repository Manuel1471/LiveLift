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

        ignored = String.split(elem(first, 2), "\n", trim: true)

        for name <-
              ~w(generated_views.js generated_views.js.map generated_views.d.ts live_lift_runtime.js live_lift_runtime.d.ts) do
          assert Enum.count(ignored, &(&1 == "/assets/js/#{name}")) == 1
        end

        assert "/_build/" in ignored
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
    File.write!(Path.join(root, ".gitignore"), "/_build/\n")

    try do
      File.cd!(root, fn ->
        assert_raise Mix.Error, ~r/expected the Phoenix colocatedHooks import/, fn ->
          Mix.Tasks.LiveLift.Install.run([])
        end

        assert File.read!("assets/js/app.js") == js
        assert File.read!("mix.exs") == mix
        assert File.read!(".gitignore") == "/_build/\n"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "an unsupported deploy alias leaves the standard hook source untouched" do
    root = temp_root()

    js = """
    import {hooks as colocatedHooks} from "phoenix-colocated/my_app"
    const liveSocket = new LiveSocket("/live", Socket, {hooks: {...colocatedHooks}})
    """

    mix = """
    "assets.build": ["compile", "esbuild my_app"],
    "assets.deploy": &deploy_assets/1
    """

    files = %{"assets/js/app.js" => js, "mix.exs" => mix, ".gitignore" => "/_build/\n"}

    try do
      File.cd!(root, fn ->
        Enum.each(files, fn {file, content} -> File.write!(file, content) end)

        assert_raise Mix.Error, ~r/unsupported Phoenix assets aliases/, fn ->
          Mix.Tasks.LiveLift.Install.run([])
        end

        for {file, content} <- files, do: assert(File.read!(file) == content)
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
