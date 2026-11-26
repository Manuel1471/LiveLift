defmodule LiveLift.ReleaseNotesTest do
  use ExUnit.Case, async: true

  @script Path.expand("../../scripts/release_notes.exs", __DIR__)

  test "release preparation keeps assets and documented installs on the Mix version" do
    dir = Path.join(System.tmp_dir!(), "live_lift_release_#{System.unique_integer([:positive])}")
    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule ReleaseNotesFixture.MixProject do
      use Mix.Project
      def project, do: [app: :live_lift, version: "0.1.0-rc.2"]
    end
    """)

    original = "# Changelog\n\n## Unreleased\n\n- New notes.\n\n## 0.1.0-rc.1\n\n- Old notes.\n"
    changelog = Path.join(dir, "CHANGELOG.md")
    File.write!(changelog, original)

    assets = Path.join(dir, "assets")
    File.mkdir!(assets)
    manifest = Path.join(assets, "package.json")
    File.write!(manifest, ~s({"name":"live-lift-assets","version":"0.1.0-rc.1"}))

    docs = Path.join(dir, "docs")
    File.mkdir!(docs)
    guide = Path.join(docs, "phoenix-integration.md")

    old_guide = """
    [Hex](https://hex.pm/packages/live_lift/0.1.0-rc.1)
    {:live_lift, "~> 0.1.0-rc.1"}
    mix igniter.install live_lift@0.1.0-rc.1 --dry-run
    mix igniter.install live_lift@0.1.0-rc.1
    mix igniter.install live_lift@path:/tmp/package
    """

    File.write!(guide, old_guide)

    assert {output, status} = run(dir, "check")
    assert status != 0
    assert output =~ "Expected version 0.1.0-rc.2 in assets/package.json"
    assert File.read!(changelog) == original

    assert {_, 0} = run(dir, "prepare")
    assert %{"version" => "0.1.0-rc.2"} = manifest |> File.read!() |> :json.decode()
    assert File.read!(guide) == String.replace(old_guide, "0.1.0-rc.1", "0.1.0-rc.2")

    assert File.read!(changelog) ==
             String.replace(original, "## Unreleased\n\n", "## Unreleased\n\n## 0.1.0-rc.2\n\n")

    assert {"## LiveLift 0.1.0-rc.2\n\n- New notes.\n", 0} = run(dir, "check")

    File.write!(guide, old_guide)
    assert {output, status} = run(dir, "check")
    assert status != 0
    assert output =~ "Expected version 0.1.0-rc.2 in the Hex installation examples"
  end

  defp run(dir, mode) do
    System.cmd("elixir", [@script, mode], cd: dir, stderr_to_stdout: true)
  end
end
