defmodule LiveLift.ReleaseNotesTest do
  use ExUnit.Case, async: true

  @script Path.expand("../../scripts/release_notes.exs", __DIR__)

  test "release preparation keeps the local asset binding on the Mix version" do
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

    assert {output, status} = run(dir, "check")
    assert status != 0
    assert output =~ "Expected version 0.1.0-rc.2 in assets/package.json"
    assert File.read!(changelog) == original

    assert {_, 0} = run(dir, "prepare")
    assert %{"version" => "0.1.0-rc.2"} = manifest |> File.read!() |> :json.decode()

    assert File.read!(changelog) ==
             String.replace(original, "## Unreleased\n\n", "## Unreleased\n\n## 0.1.0-rc.2\n\n")

    assert {"## LiveLift 0.1.0-rc.2\n\n- New notes.\n", 0} = run(dir, "check")
  end

  defp run(dir, mode) do
    System.cmd("elixir", [@script, mode], cd: dir, stderr_to_stdout: true)
  end
end
