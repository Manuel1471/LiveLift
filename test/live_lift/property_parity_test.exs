defmodule LiveLift.PropertyParityTest do
  use ExUnit.Case, async: true

  defmodule Actions do
    use LiveLift.Client

    defclient(reduce_numbers(state),
      do: %{value: Enum.reduce(state.items, fn item, accumulator -> item + accumulator end)}
    )

    defclient(join_values(state), do: %{joined: Enum.join(state.items, state.separator)})

    defclient(flat_invalid(state),
      do: %{items: Enum.flat_map(state.items, fn item -> item.id end)}
    )

    defclient(split_values(state), do: %{parts: String.split(state.value, state.pattern)})

    defclient(replace_values(state),
      do: %{value: String.replace(state.value, state.pattern, state.replacement)}
    )

    defclient(replace_invalid(state),
      do: %{value: String.replace(state.value, "a", fn _match -> nil end)}
    )

    defclient(check(state),
      do: %{
        count: state.count + state.step,
        subtracted: state.count - state.step,
        multiplied: state.count * state.step,
        remainder: rem(state.count, if(state.step == 0, do: 1, else: state.step)),
        less: state.count < state.step,
        less_or_equal: state.count <= state.step,
        greater: state.count > state.step,
        greater_or_equal: state.count >= state.step,
        different: state.items != state.other,
        positive: +state.count,
        negative: -state.count,
        negated: !state.flag,
        and_value: state.flag && state.label,
        or_value: state.flag || state.label,
        same: state.items == state.other,
        joined: state.items ++ state.other,
        item_count: length(state.items),
        mapped: Enum.map(state.items, fn item -> Map.put(item, :seen, true) end),
        filtered: Enum.filter(state.items, fn item -> item.keep end),
        rejected: Enum.reject(state.items, fn item -> item.keep end),
        reversed: Enum.reverse(state.items),
        piped_ids: state.items |> Enum.map(fn item -> item.id end) |> Enum.reverse(),
        piped_graphemes: state.label |> String.trim() |> String.length(),
        any: Enum.any?(state.items, fn item -> item.keep end),
        all: Enum.all?(state.items, fn item -> item.keep end),
        found: Enum.find(state.items, fn item -> item.keep end),
        found_or: Enum.find(state.items, %{id: -1, keep: false}, fn item -> item.keep end),
        found_truthy: Enum.find(state.items, fn item -> item.keep || state.flag end),
        reduced_total: Enum.reduce(state.items, 0, fn item, total -> item.id + total end),
        reduced_value:
          Enum.reduce(state.items, state.flag, fn item, value ->
            if item.keep, do: item.id, else: value
          end),
        reduced_unseeded:
          if state.items == [] do
            nil
          else
            Enum.reduce(state.items, fn item, previous ->
              if item.keep, do: item, else: previous
            end)
          end,
        sorted_values: Enum.sort_by(state.sortable, fn value -> value end),
        sorted_items: Enum.sort_by(state.items, fn item -> item.id end),
        counted: Enum.count(state.items),
        counted_kept: Enum.count(state.items, fn item -> item.keep end),
        counted_truthy: Enum.count(state.items, fn item -> item.keep || state.flag end),
        joined_values: Enum.join(state.joinables, state.separator),
        joined_default: Enum.join(state.joinables),
        flat_doubled: Enum.flat_map(state.items, fn item -> [item, item] end),
        flat_kept:
          Enum.flat_map(state.items, fn item -> if item.keep, do: [item.id], else: [] end),
        indexed_items:
          Enum.with_index(state.items, fn item, index -> %{id: item.id, index: index} end),
        member: Enum.member?(state.items, state.target),
        list_deleted: List.delete(state.items, state.target),
        list_deleted_at: List.delete_at(state.items, state.amount),
        list_replaced_at: List.replace_at(state.items, state.amount, state.target),
        list_inserted_at: List.insert_at(state.items, state.amount, state.target),
        list_exact: List.delete([[1.0], [1], [1]], [1]) |> length(),
        list_exact_order: List.delete([1.0, 1], 1) |> Enum.join(),
        list_signed_zero: List.delete([0.0, -0.0], -0.0) |> Enum.join(),
        taken: Enum.take(state.items, state.amount),
        dropped: Enum.drop(state.items, state.amount),
        unique: Enum.uniq(state.items),
        label: state.label <> "!",
        contains: String.contains?(state.label, state.query),
        trimmed: String.trim(state.label),
        downcased: String.downcase(state.label),
        split_whitespace: String.split(state.label),
        split_pattern: String.split(state.label, state.split_pattern),
        split_trim: String.split(state.label, state.split_pattern, trim: true),
        split_parts: String.split(state.label, state.split_pattern, trim: true, parts: 2),
        split_overlap: String.split("ab", ["a", "ab"]),
        replaced: String.replace(state.label, state.replace_pattern, state.replacement),
        replaced_once:
          String.replace(state.label, state.replace_pattern, state.replacement, global: false),
        replaced_callback:
          String.replace(state.label, state.replace_pattern, fn match -> "[" <> match <> "]" end),
        replaced_iodata:
          String.replace(state.label, state.replace_pattern, fn match -> ["<", match, [33]] end),
        replaced_bom: String.replace("x", "x", fn _match -> [239, 187, 191] end),
        replaced_utf8_bytes: String.replace("x", "x", fn _match -> [195, 169] end),
        replaced_overlap: String.replace("ab", ["a", "ab"], "X"),
        graphemes: String.length(state.label),
        choice: if(state.flag, do: "yes", else: "no"),
        cond_choice:
          cond do
            state.flag == false -> "false"
            state.flag == nil -> "nil"
            state.count < 0 -> "negative"
            true -> "other"
          end,
        absent: Map.get(state.optional, :missing, "fallback"),
        maybe_present: Map.get(state.optional, :present),
        added: Map.put(state.optional, :added, state.flag),
        merged: Map.merge(state.optional, %{present: state.flag, label: state.label}),
        removed: Map.delete(state.optional, :present),
        key_count: state.optional |> Map.keys() |> length(),
        value_count: Enum.count(Map.values(state.optional)),
        ordered_key_names:
          state.optional |> Map.keys() |> Enum.map(&Atom.to_string/1) |> Enum.sort(),
        picked: Map.take(state.optional, [:present, :missing]),
        integer_label: Integer.to_string(state.count)
      }
    )
  end

  test "Enum.reduce/2 rejects an empty list on both sides" do
    assert_raise Enum.EmptyError, fn -> Actions.reduce_numbers(%{items: []}) end

    javascript =
      LiveLift.Client.Compiler.compile_module(Actions) <>
        "try { actions.reduce_numbers({items: []}); process.exit(1); } " <>
        "catch (error) { if (!error.message.includes('nonempty list')) process.exit(2); }"

    assert {"", 0} = System.cmd("node", ["--input-type=module", "--eval", javascript])
  end

  test "Enum.join rejects maps and invalid chardata on both sides" do
    assert_raise Protocol.UndefinedError, fn ->
      Actions.join_values(%{items: [%{}], separator: ","})
    end

    assert_raise UnicodeConversionError, fn ->
      Actions.join_values(%{items: [[0xD800]], separator: ","})
    end

    source =
      LiveLift.Client.Compiler.compile_module(Actions) <>
        "for (const item of [{}, [0xd800]]) { " <>
        "try { actions.join_values({items: [item], separator: ','}); process.exit(1); } " <>
        "catch (error) { if (!error.message.includes('LiveLift')) process.exit(2); } }"

    assert {"", 0} = System.cmd("node", ["--input-type=module", "--eval", source])
  end

  test "Enum.flat_map rejects a scalar callback result on both sides" do
    assert_raise Protocol.UndefinedError, fn ->
      Actions.flat_invalid(%{items: [%{id: 1}]})
    end

    source =
      LiveLift.Client.Compiler.compile_module(Actions) <>
        "try { actions.flat_invalid({items: [{id: 1}]}); process.exit(1); } " <>
        "catch (error) { if (!error.message.includes('expected a list')) process.exit(2); }"

    assert {"", 0} = System.cmd("node", ["--input-type=module", "--eval", source])
  end

  test "String.split rejects an empty pattern inside a list on both sides" do
    assert_raise ArgumentError, fn ->
      Actions.split_values(%{value: "a,b", pattern: ["", ","]})
    end

    source =
      LiveLift.Client.Compiler.compile_module(Actions) <>
        "try { actions.split_values({value: 'a,b', pattern: ['', ',']}); process.exit(1); } " <>
        "catch (error) { if (!error.message.includes('nonempty strings')) process.exit(2); }"

    assert {"", 0} = System.cmd("node", ["--input-type=module", "--eval", source])
  end

  test "String.replace rejects an empty pattern inside a list on both sides" do
    assert_raise ArgumentError, fn ->
      Actions.replace_values(%{value: "a,b", pattern: ["", ","], replacement: "x"})
    end

    source =
      LiveLift.Client.Compiler.compile_module(Actions) <>
        "try { actions.replace_values({value: 'a,b', pattern: ['', ','], replacement: 'x'}); process.exit(1); } " <>
        "catch (error) { if (!error.message.includes('nonempty strings')) process.exit(2); }"

    assert {"", 0} = System.cmd("node", ["--input-type=module", "--eval", source])
  end

  test "String.replace rejects a callback result that is not iodata on both sides" do
    assert_raise ArgumentError, fn -> Actions.replace_invalid(%{value: "a"}) end

    source =
      LiveLift.Client.Compiler.compile_module(Actions) <>
        "try { actions.replace_invalid({value: 'a'}); process.exit(1); } " <>
        "catch (error) { if (!error.message.includes('iodata')) process.exit(2); }"

    assert {"", 0} = System.cmd("node", ["--input-type=module", "--eval", source])
  end

  test "1,000 seeded states keep Elixir and generated JavaScript equal" do
    item = StreamData.fixed_map(%{id: StreamData.integer(-100..100), keep: StreamData.boolean()})
    items = StreamData.list_of(item, max_length: 6)

    sortable =
      StreamData.list_of(
        StreamData.member_of([
          nil,
          false,
          true,
          -2,
          0,
          2,
          "",
          "a",
          "\uE000",
          "\u{10000}",
          [],
          [1],
          [1, 2],
          %{},
          %{a: 1},
          %{b: 0},
          %{a: 1, b: 2}
        ]),
        max_length: 8
      )

    joinables =
      StreamData.list_of(
        StreamData.member_of(["", "é", "😀", -2, 0, 2, nil, false, true, [], [65], [[65], "b"]]),
        max_length: 8
      )

    label =
      StreamData.list_of(
        StreamData.member_of([
          "a",
          "é",
          "😀",
          "é",
          "Σ",
          "ΟΣ",
          "a,,b,",
          "a  b",
          "İ",
          "ẞ",
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
          "\u00A0",
          "\u202F",
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
        sortable: sortable,
        joinables: joinables,
        separator: StreamData.member_of(["", ",", " · ", "😀"]),
        split_pattern: StreamData.member_of(["", ",", "é", "😀", [",", ";"], [], ["a", "aa"]]),
        replace_pattern: StreamData.member_of(["", ",", "é", "😀", [",", ";"], [], ["a", "aa"]]),
        replacement: StreamData.member_of(["", "X", "<&>", "😀", "$&", "\\0"]),
        amount: StreamData.integer(-12..12),
        other: items,
        target: item,
        label: label,
        query: query,
        flag: StreamData.member_of([true, false, nil, 0, [], ""]),
        optional:
          StreamData.one_of([
            StreamData.constant(%{}),
            StreamData.fixed_map(%{present: StreamData.member_of([nil, false, 0, "é"])}),
            StreamData.fixed_map(%{
              present: StreamData.member_of([nil, false, 0, "é"]),
              missing: StreamData.member_of([nil, true, "<value>"]),
              extra: StreamData.integer(-5..5)
            })
          ])
      })

    cases =
      [
        %{
          count: 0,
          step: 0,
          items: [],
          sortable: ["\u{10000}", "\uE000", nil, false, true],
          joinables: [],
          separator: ",",
          split_pattern: "",
          replace_pattern: "",
          replacement: "X",
          amount: -1,
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
          sortable: [%{b: 0}, %{a: 1}, %{}, [], "a"],
          joinables: [nil, false, 0, [65]],
          separator: " · ",
          split_pattern: [",", ";"],
          replace_pattern: [",", ";"],
          replacement: "<&>",
          amount: -12,
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
          items: [%{id: 1, keep: true}, %{id: 1, keep: true}],
          sortable: [[1, 2], [1], 2, 0, -2],
          joinables: ["😀", [[65], "b"], true],
          separator: "😀",
          split_pattern: "",
          replace_pattern: ["a", "aa"],
          replacement: "😀",
          amount: 12,
          other: [],
          target: %{id: 0, keep: true},
          label: "\u0085ΟΣ\uFEFF",
          query: "é",
          flag: false,
          optional: %{}
        }
      ] ++
        Enum.map([-9_007_199_254_740_991, 9_007_199_254_740_991], fn count ->
          %{
            count: count,
            step: 0,
            items: [],
            sortable: [],
            joinables: [],
            separator: "",
            split_pattern: ",",
            replace_pattern: "",
            replacement: "X",
            amount: 0,
            other: [],
            target: %{id: 0, keep: false},
            label: "",
            query: "",
            flag: false,
            optional: %{}
          }
        end) ++ (state |> StreamData.seeded(20_261_106) |> Enum.take(1_000))

    large_map = Map.new(1..40, fn index -> {String.to_atom("key_#{index}"), index} end)
    cases = [Map.replace!(hd(cases), :optional, large_map) | cases]
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
