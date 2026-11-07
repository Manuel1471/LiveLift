defmodule LiveLift.PropertyParityTest do
  use ExUnit.Case, async: true

  defmodule Actions do
    use LiveLift.Client

    defclient(check(state),
      do: %{
        count: state.count + state.step,
        same: state.items == state.other,
        filtered: Enum.filter(state.items, fn item -> item.keep end),
        any: Enum.any?(state.items, fn item -> item.keep end),
        all: Enum.all?(state.items, fn item -> item.keep end),
        member: Enum.member?(state.items, state.target),
        label: state.label <> "!",
        contains: String.contains?(state.label, state.query),
        trimmed: String.trim(state.label),
        graphemes: String.length(state.label),
        choice: if(state.flag, do: "yes", else: "no"),
        absent: Map.get(state.optional, :missing, "fallback")
      }
    )
  end

  test "1,000 seeded states keep Elixir and generated JavaScript equal" do
    item = StreamData.fixed_map(%{id: StreamData.integer(-100..100), keep: StreamData.boolean()})
    items = StreamData.list_of(item, max_length: 6)

    label =
      StreamData.list_of(
        StreamData.member_of([
          "a",
          "é",
          "😀",
          "é",
          "👨‍👩‍👧‍👦",
          "🇲🇽",
          "👍🏽",
          "क्‍ष",
          "\r\n",
          "&",
          "<",
          "\"",
          " ",
          "\t",
          "\u0085",
          "\uFEFF",
          "\u2000"
        ]),
        max_length: 8
      )
      |> StreamData.map(&Enum.join/1)

    query =
      StreamData.one_of([
        StreamData.member_of(["", "a", "é", "😀", "é", "&", "missing"]),
        StreamData.list_of(StreamData.member_of(["", "a", "é", "😀", "missing"]),
          max_length: 4
        )
      ])

    state =
      StreamData.fixed_map(%{
        count: StreamData.integer(-1_000..1_000),
        step: StreamData.integer(-1_000..1_000),
        items: items,
        other: items,
        target: item,
        label: label,
        query: query,
        flag: StreamData.member_of([true, false, nil, 0, [], ""]),
        optional: StreamData.constant(%{present: nil})
      })

    cases =
      [
        %{
          count: 0,
          step: 0,
          items: [],
          other: [],
          target: %{id: 1, keep: false},
          label: "",
          query: [],
          flag: nil,
          optional: %{}
        },
        %{
          count: 1,
          step: -1,
          items: [%{id: 1, keep: false}],
          other: [%{id: 1, keep: false}],
          target: %{id: 1, keep: false},
          label: "😀&",
          query: ["", "missing"],
          flag: 0,
          optional: %{}
        },
        %{
          count: 0,
          step: 1,
          items: [],
          other: [],
          target: %{id: 0, keep: true},
          label: "\u0085é\uFEFF",
          query: "é",
          flag: false,
          optional: %{}
        }
      ] ++ (state |> StreamData.seeded(20_261_106) |> Enum.take(1_000))

    Enum.each(cases, &LiveLift.State.validate!/1)
    expected = Enum.map(cases, &Actions.check/1) |> Jason.encode!() |> Jason.decode!()

    directory =
      Path.join(System.tmp_dir!(), "live_lift_parity_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    script = Path.join(directory, "actions.mjs")
    input = Path.join(directory, "cases.json")

    try do
      File.write!(input, Jason.encode!(cases))

      File.write!(
        script,
        LiveLift.Client.Compiler.compile_module(Actions) <>
          """
          import {readFileSync} from "node:fs";
          const cases = JSON.parse(readFileSync(process.argv[2], "utf8"));
          console.log(JSON.stringify(cases.map((state) => actions.check(state))));
          """
      )

      {output, 0} = System.cmd("node", [script, input])
      actual = Jason.decode!(output)
      assert actual == expected
    after
      File.rm_rf!(directory)
    end
  end
end
