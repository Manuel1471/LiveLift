defmodule LiveLift.CompilerFuzzTest do
  use ExUnit.Case, async: true

  alias LiveLift.Client.Compiler

  test "1,000 seeded expression variants either compile to valid JavaScript or reject explicitly" do
    leaves =
      [
        "nil",
        "false",
        "true",
        "0",
        "-1",
        "\"<script>\"",
        "state.count",
        "state.label",
        "state.items",
        "[1, nil]",
        "%{count: 1}",
        "missing",
        "self()"
      ]

    operators = ["+", "==", "&&", "++", "<>"]
    :rand.seed(:exsplus, {20_261_107, 7, 1})

    sources =
      for _ <- 1..1_000 do
        left = Enum.at(leaves, :rand.uniform(length(leaves)) - 1)
        right = Enum.at(leaves, :rand.uniform(length(leaves)) - 1)
        operator = Enum.at(operators, :rand.uniform(length(operators)) - 1)

        case :rand.uniform(6) do
          1 -> "#{left} #{operator} #{right}"
          2 -> "if(#{left}, do: #{right})"
          3 -> "if(#{left}, do: #{right}, else: #{left})"
          4 -> "Enum.take(#{left}, #{right})"
          5 -> "Map.get(#{left}, :count, #{right})"
          6 -> "if(#{left}, else: #{right})"
        end
      end

    compiled =
      Enum.flat_map(sources, fn source ->
        ast = Code.string_to_quoted!(source, file: "compiler_fuzz.ex")

        try do
          [Compiler.compile_action(:check, :state, ast)]
        rescue
          error in ArgumentError ->
            assert Exception.message(error) =~ "unsupported"
            []
        end
      end)

    assert compiled != []

    script =
      compiled
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {action, index} ->
        "const actions#{index} = {#{action}};"
      end)

    path =
      Path.join(
        System.tmp_dir!(),
        "live_lift_compiler_fuzz_#{System.unique_integer([:positive])}.mjs"
      )

    try do
      File.write!(path, script)
      {_output, 0} = System.cmd("node", ["--check", path])
    after
      File.rm(path)
    end
  end
end
