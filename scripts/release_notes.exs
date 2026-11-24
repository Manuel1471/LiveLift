Mix.start()

version =
  Mix.Project.in_project(:live_lift, ".", fn _ ->
    Mix.Project.config() |> Keyword.fetch!(:version) |> Version.parse!() |> to_string()
  end)

path = "CHANGELOG.md"
asset_manifest = "assets/package.json"
asset_version = asset_manifest |> File.read!() |> :json.decode() |> Map.fetch!("version")
[title | raw_sections] = Regex.split(~r/^## /m, File.read!(path))

sections =
  Enum.map(raw_sections, fn section ->
    [heading, body] = String.split(section, "\n", parts: 2)
    {heading, body}
  end)

unless Enum.uniq_by(sections, &elem(&1, 0)) == sections do
  Mix.raise("CHANGELOG.md contains duplicate section headings")
end

case {System.argv(), sections} do
  {["prepare"], [{"Unreleased", notes}, {previous, _} | _]} ->
    unless String.trim(notes) != "" and Version.compare(version, previous) == :gt do
      Mix.raise("Bump the Mix version and add release notes under Unreleased before preparing")
    end

    if asset_version != version do
      npm =
        System.find_executable("npm") ||
          Mix.raise("Install npm to update the local asset manifest")

      case System.cmd(npm, ["pkg", "set", "--prefix", "assets", "version=#{version}"],
             stderr_to_stdout: true
           ) do
        {_, 0} -> :ok
        {output, _} -> Mix.raise("Could not update #{asset_manifest}\n#{output}")
      end
    end

    history = Enum.map(tl(raw_sections), &["## ", &1])
    File.write!(path, [title, "## Unreleased\n\n## ", version, "\n", notes, history])
    IO.puts("Prepared CHANGELOG.md and #{asset_manifest} for LiveLift #{version}")

  {["check"], _} ->
    unless asset_version == version do
      Mix.raise("Expected version #{version} in #{asset_manifest}; found #{asset_version}")
    end

    released = Enum.reject(sections, &match?({"Unreleased", _}, &1))

    case released do
      [{^version, notes} | _] ->
        if String.trim(notes) == "", do: Mix.raise("CHANGELOG.md has no notes for #{version}")
        IO.puts("## LiveLift #{version}\n\n#{String.trim(notes)}")

      _ ->
        Mix.raise("Expected #{version} as the latest release in CHANGELOG.md")
    end

  _ ->
    Mix.raise("Usage: elixir scripts/release_notes.exs check|prepare")
end
