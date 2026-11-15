defmodule LiveLift.CaseParityTest do
  use ExUnit.Case, async: true

  alias LiveLift.{Client.Compiler, FloatWire}

  defmodule Actions do
    use LiveLift.Client

    defclient(classify(state),
      do:
        case state.value do
          nil -> "nil"
          1 -> "integer"
          1.0 -> "float"
          -1 -> "negative integer"
          -0.0 -> "zero float"
          [head | tail] -> %{head: head, tail: tail}
          %{nested: %{id: id}, items: [first | rest]} -> %{id: id, first: first, rest: rest}
          %{id: id} -> %{id: id}
          _ -> "other"
        end
    )

    defclient(exact_list(state),
      do:
        case state.value do
          [first, second] -> %{first: first, second: second}
          [] -> "empty"
          _ -> "other"
        end
    )

    defclient(no_match(state),
      do:
        case state.value do
          42 -> "found"
        end
    )

    defclient(lazy(state),
      do:
        case state.value do
          1 -> 1
          _ -> state.missing
        end
    )

    defclient(nested(state),
      do:
        case state.value do
          [%{id: id} | _] ->
            case id do
              1 -> "one"
              other -> Integer.to_string(other)
            end

          _ ->
            nil
        end
    )
  end

  test "1,000 seeded cases preserve typed patterns, lists and partial maps" do
    values =
      [
        nil,
        0,
        1,
        1.0,
        -1,
        2.0,
        -0.0,
        0.0,
        "1",
        false,
        [],
        [1],
        [1, 2],
        %{id: 4},
        %{id: nil, extra: 5},
        %{nested: %{id: 9}, items: [1, 2], extra: true}
      ] ++
        (StreamData.one_of([
           StreamData.integer(-10..10),
           StreamData.member_of([1.0, 2.0, -0.0, nil, false, "hello"]),
           StreamData.list_of(StreamData.integer(-4..4), max_length: 4),
           StreamData.fixed_map(%{id: StreamData.integer(0..10), extra: StreamData.boolean()})
         ])
         |> StreamData.seeded(20_261_115)
         |> Enum.take(1_000))

    states = Enum.map(values, &%{value: &1})
    Enum.each(states, &LiveLift.State.validate!/1)

    for action <- [:classify, :exact_list] do
      expected = states |> Enum.map(&apply(Actions, action, [&1])) |> FloatWire.encode()
      input = states |> FloatWire.encode() |> Jason.encode!()

      actual =
        run_node!(
          "console.log(JSON.stringify(#{input}.map((state) => actions.#{action}(state))));"
        )

      assert Jason.decode!(actual) == expected |> Jason.encode!() |> Jason.decode!()
    end
  end

  test "case raises when no clause matches and skips unused bodies" do
    assert Actions.lazy(%{value: 1}) == 1
    assert run_node!("console.log(actions.lazy({value: 1}));") == "1\n"

    assert_raise CaseClauseError, fn -> Actions.no_match(%{value: 2}) end
    {output, status} = run_node_result("actions.no_match({value: 2});")
    assert status != 0
    assert output =~ "LiveLift case has no matching clause"
  end

  test "nested cases preserve captured bindings" do
    for {value, expected} <- [{[%{id: 1}], "one"}, {[%{id: 7}, %{id: 2}], "7"}, {[], nil}] do
      assert Actions.nested(%{value: value}) == expected
      input = %{value: value} |> Jason.encode!()

      assert run_node!("console.log(JSON.stringify(actions.nested(#{input})));") |> String.trim() ==
               Jason.encode!(expected)
    end
  end

  test "pin and tuple patterns fail before JavaScript generation" do
    assert_raise ArgumentError, ~r/unsupported client case pattern.*use literals/, fn ->
      Compiler.compile_action(
        :bad,
        :state,
        quote(
          do:
            case state.value do
              {a, b} -> a
            end
        )
      )
    end

    assert_raise ArgumentError, ~r/unsupported client case map pattern.*safe atom keys/, fn ->
      Compiler.compile_action(
        :bad,
        :state,
        quote(
          do:
            case state.value do
              %{"id" => id} -> id
            end
        )
      )
    end

    assert_raise ArgumentError,
                 ~r/unsupported client case pattern: bind each variable once/,
                 fn ->
                   Compiler.compile_action(
                     :bad,
                     :state,
                     quote(
                       do:
                         case state.value do
                           [item, item] -> item
                         end
                     )
                   )
                 end

    assert_raise ArgumentError, ~r/unsupported client case pattern.*use literals/, fn ->
      Compiler.compile_action(
        :bad,
        :state,
        quote(
          do:
            case state.value do
              ^state -> 1
            end
        )
      )
    end
  end

  defp run_node!(action) do
    {output, 0} = run_node_result(action)
    output
  end

  defp run_node_result(action) do
    path =
      Path.join(System.tmp_dir!(), "live_lift_case_#{System.unique_integer([:positive])}.mjs")

    try do
      File.write!(path, Compiler.compile_module(Actions) <> "\n" <> action)
      System.cmd("node", [path], stderr_to_stdout: true)
    after
      File.rm(path)
    end
  end
end
