defmodule LiveLift.ClientTest do
  use ExUnit.Case, async: true

  alias LiveLift.Client.Compiler

  defmodule CounterActions do
    use LiveLift.Client

    defclient(increment(count), do: count + 1)
    defclient(decrement(count), do: count - 1)
    defclient(double_plus_one(count), do: count * 2 + 1)
    defclient(advance(state), do: %{count: state.count + state.step, step: state.step})
  end

  defmodule TemplatedActions do
    use LiveLift.Client

    client_template("<output>{@count}</output>")
    defclient(increment(state), do: %{count: state.count + 1})
  end

  defmodule MissingAction do
    use LiveLift.Client

    client_template("<button $click=\"missing\">Go</button>")
  end

  defmodule ReadOnlyView do
    use LiveLift.Client

    client_template("<p>{@value}</p>")
  end

  defmodule ConditionalView do
    use LiveLift.Client

    defclient(label(state), do: if(state.enabled == true, do: "on", else: "off"))
    defclient(optional(state), do: if(state.name, do: state.name, else: "anonymous"))
  end

  defmodule ParityActions do
    use LiveLift.Client

    defclient(sum(state), do: %{value: state.value + state.step})
    defclient(same(state), do: %{same: state.left == state.right})
    defclient(choose(state), do: %{value: if(state.flag, do: "yes", else: "no")})
  end

  defmodule ListActions do
    use LiveLift.Client

    defclient(add(state),
      do: %{
        items: state.items ++ [%{id: state.next_id, name: state.draft}],
        next_id: state.next_id + 1,
        draft: ""
      }
    )

    defclient(remove(state, event),
      do: %{
        items: Enum.reject(state.items, fn item -> item.id == event.params.id end),
        next_id: state.next_id,
        draft: state.draft
      }
    )
  end

  defmodule ButtonComponent do
    use LiveLift.Client.Component
    client_template("<button $click=\"missing\">Go</button>")
  end

  defmodule ComponentParent do
    use LiveLift.Client
    client_template("<LiveLift.ClientTest.ButtonComponent />")
  end

  defmodule ValidComponent do
    use LiveLift.Client.Component
    client_template("<button $click=\"go\">Go</button>")
  end

  defmodule ValidParent do
    use LiveLift.Client
    client_template("<LiveLift.ClientTest.ValidComponent />")
    defclient(go(state), do: state)
  end

  defmodule ExtendedParity do
    use LiveLift.Client

    defclient(transform(state),
      do: %{
        doubled: Enum.map(state.items, fn item -> Map.put(item, :n, item.n * 2) end),
        reversed: Enum.reverse(state.items),
        size: length(state.items),
        minus: state.count - 2,
        negative: -state.count,
        positive: +state.count,
        toggled: !state.flag,
        different: state.count != 0
      }
    )
  end

  test "defines normal Elixir functions and compiles their expressions" do
    assert CounterActions.increment(10) == 11
    assert CounterActions.decrement(10) == 9
    assert CounterActions.double_plus_one(10) == 21
    assert CounterActions.advance(%{count: 10, step: 3}) == %{count: 13, step: 3}

    javascript = Compiler.compile_module(CounterActions)
    assert javascript =~ "function __liveLiftInt"
    assert javascript =~ "function __liveLiftGet"
    assert javascript =~ "increment: (count) => __liveLiftInt"
    assert javascript =~ ~s|__liveLiftGet(state, "count")|
  end

  test "rejects unsupported syntax" do
    assert_raise ArgumentError, ~r/unsupported client expression/, fn ->
      Code.compile_string("""
      defmodule UnsupportedAction do
        use LiveLift.Client
        defclient halve(count), do: div(count, 2)
      end
      """)
    end
  end

  test "compiles primitive values and Elixir conditional truthiness" do
    assert ConditionalView.label(%{enabled: true}) == "on"
    assert ConditionalView.label(%{enabled: false}) == "off"
    assert ConditionalView.optional(%{name: nil}) == "anonymous"

    javascript = Compiler.compile_module(ConditionalView)
    assert javascript =~ ~s|__liveLiftEqual(__liveLiftGet(state, "enabled"), true)|
    assert javascript =~ "!== false"
    assert javascript =~ "!== null"
    assert javascript =~ ~s(? "on" : "off")
  end

  test "includes the app template in generated JavaScript" do
    javascript = Compiler.compile_module(TemplatedActions)

    assert javascript =~ "export const template = "
    assert javascript =~ ~s("type":"binding")
    assert javascript =~ "increment: (state) => ({count: __liveLiftInt"
  end

  test "rejects a template event without a matching action" do
    assert_raise ArgumentError, ~r/unknown client template action: missing/, fn ->
      Compiler.compile_module(MissingAction)
    end
  end

  test "builds a registry without manual JavaScript module mapping" do
    javascript = Compiler.compile_registry([TemplatedActions, ReadOnlyView])

    assert javascript =~ "export const views = {"
    assert javascript =~ "\"LiveLift.ClientTest.TemplatedActions\""
    assert javascript =~ "\"LiveLift.ClientTest.ReadOnlyView\""
    assert javascript =~ "actions: {increment: (state) => ({count: __liveLiftInt"
    assert javascript =~ "template: "
  end

  test "generated JavaScript agrees with Elixir on supported values" do
    cases = [
      {"sum", %{value: 10, step: 2}, ParityActions.sum(%{value: 10, step: 2})},
      {"same", %{left: %{a: [1, false]}, right: %{a: [1, false]}}, %{same: true}},
      {"same", %{left: [1, nil], right: [1, false]}, %{same: false}},
      {"choose", %{flag: false}, %{value: "no"}},
      {"choose", %{flag: nil}, %{value: "no"}},
      {"choose", %{flag: 0}, %{value: "yes"}}
    ]

    javascript = Compiler.compile_module(ParityActions)

    for {name, input, expected} <- cases do
      source =
        javascript <>
          "\nconsole.log(JSON.stringify(actions[#{Jason.encode!(name)}](#{Jason.encode!(input)})));"

      {output, 0} = System.cmd("node", ["--input-type=module", "--eval", source])
      assert Jason.decode!(output) == Jason.decode!(Jason.encode!(expected))
    end
  end

  test "generated JavaScript rejects unsafe arithmetic instead of changing Elixir semantics" do
    javascript = Compiler.compile_module(ParityActions)
    source = javascript <> "\nactions.sum({value: Number.MAX_SAFE_INTEGER, step: 1});"

    {_output, status} =
      System.cmd("node", ["--input-type=module", "--eval", source], stderr_to_stdout: true)

    assert status != 0
  end

  test "compiled list actions agree with Elixir and receive typed event parameters" do
    state = %{items: [%{id: 1, name: "A"}], next_id: 2, draft: "B"}
    event = %{params: %{id: 1}, value: nil, checked: false}
    expected = state |> ListActions.add() |> ListActions.remove(event)
    javascript = Compiler.compile_module(ListActions)

    source =
      javascript <>
        "\nconst state = actions.add(#{Jason.encode!(state)}); console.log(JSON.stringify(actions.remove(state, #{Jason.encode!(event)})));"

    {output, 0} = System.cmd("node", ["--input-type=module", "--eval", source])
    assert Jason.decode!(output) == Jason.decode!(Jason.encode!(expected))
  end

  test "checks nested component actions against the parent and bundles dependencies" do
    assert_raise ArgumentError, ~r/unknown client template action: missing/, fn ->
      Compiler.compile_registry([ComponentParent])
    end

    javascript = Compiler.compile_registry([ValidParent])
    assert javascript =~ "LiveLift.ClientTest.ValidComponent"
  end

  test "extended list, map, unary, arithmetic, and comparison expressions keep parity" do
    state = %{items: [%{n: 2}, %{n: 3}], count: 5, flag: false}
    expected = ExtendedParity.transform(state)
    javascript = Compiler.compile_module(ExtendedParity)

    source =
      javascript <> "\nconsole.log(JSON.stringify(actions.transform(#{Jason.encode!(state)})));"

    {output, 0} = System.cmd("node", ["--input-type=module", "--eval", source])
    assert Jason.decode!(output) == Jason.decode!(Jason.encode!(expected))
  end
end
