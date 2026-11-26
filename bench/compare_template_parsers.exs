defmodule LiveLift.TemplateParserCorpus do
  alias LiveLift.Template
  alias LiveLift.Template.{FallbackParser, Parser}
  alias Phoenix.LiveView.TagEngine.Parser, as: LiveViewParser

  def run(mode, root) when mode in ["demo", "public"] do
    unless Code.ensure_loaded?(LiveViewParser) and function_exported?(LiveViewParser, :parse!, 2) do
      raise "The LiveView parser is unavailable; cannot compare the two parser paths"
    end

    templates = Enum.flat_map(source_files(root), &templates/1)
    if mode == "demo" and templates == [], do: raise("No HEEx templates found in #{root}")

    results = Enum.frequencies_by(templates, &compare(&1, root, mode))

    IO.puts(
      Enum.map_join([:matched, :rejected, :different_rejection, :different_tree], "\t", fn key ->
        Map.get(results, key, 0)
      end)
    )

    if results[:different_tree] ||
         (mode == "demo" && (results[:different_rejection] || !results[:matched])) do
      raise "Template parser parity failed for #{root}"
    end
  end

  defp source_files(directory) do
    directory
    |> File.ls!()
    |> Enum.sort()
    |> Enum.flat_map(fn name ->
      path = Path.join(directory, name)

      case File.lstat!(path).type do
        :directory -> source_files(path)
        :regular -> if Path.extname(path) in [".ex", ".heex"], do: [path], else: []
        _ -> []
      end
    end)
  end

  defp templates(path) do
    source = File.read!(path)

    if Path.extname(path) == ".heex" do
      [{path, 1, source}]
    else
      ast = Code.string_to_quoted!(source, file: path, token_metadata: true)

      {_, sigils} =
        Macro.prewalk(ast, [], fn
          {:sigil_H, meta, [{:<<>>, _, [body]}, []]} = node, acc when is_binary(body) ->
            line = meta[:line] + if(meta[:delimiter] in [~s("""), "'''"], do: 1, else: 0)
            {node, [{path, line, body} | acc]}

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(sigils)
    end
  end

  defp compare({file, line, source}, root, mode) do
    file = Path.relative_to(file, root)
    adapted = compile(fn -> Parser.parse_with!(source, file, LiveViewParser, line) end, file)
    fallback = compile(fn -> FallbackParser.parse!(source, file, line) end, file)

    case {adapted, fallback} do
      {{:ok, tree}, {:ok, tree}} ->
        :matched

      {{:error, code}, {:error, code}} ->
        :rejected

      {{:error, first}, {:error, second}} ->
        if mode == "demo", do: IO.puts(:stderr, "#{file}:#{line}: #{first} vs #{second}")
        :different_rejection

      {{:ok, _}, {:ok, _}} ->
        IO.puts(:stderr, "#{file}:#{line}: different compiled trees")
        :different_tree

      {first, second} ->
        IO.puts(
          :stderr,
          "#{file}:#{line}: adapter #{describe(first)}, fallback #{describe(second)}"
        )

        :different_tree
    end
  end

  defp describe({:ok, _}), do: "compiled"
  defp describe({:error, code}), do: "rejected with #{code}"

  defp compile(parse, file) do
    {:ok, Template.compile_parsed(parse.(), file, {:liveview, %{}})}
  rescue
    error in ArgumentError ->
      case Regex.run(~r|See docs/errors/(E\d{3})\.md|, Exception.message(error),
             capture: :all_but_first
           ) do
        [code] -> {:error, code}
        _ -> reraise error, __STACKTRACE__
      end
  end
end

[mode, root] = System.argv()
LiveLift.TemplateParserCorpus.run(mode, root)
