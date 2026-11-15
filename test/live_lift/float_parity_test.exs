defmodule LiveLift.FloatParityTest do
  use ExUnit.Case, async: true

  alias LiveLift.{Client.Compiler, FloatWire, Template}

  defmodule Actions do
    use LiveLift.Client

    defclient(calculate(state),
      do: %{
        sum: state.left + state.right,
        difference: state.left - state.right,
        product: state.left * state.right,
        negative: -state.left,
        positive: +state.left,
        less: state.left < state.right,
        equal: state.left == state.right,
        nested_equal: state.items == state.other
      }
    )

    defclient(sort_numbers(state),
      do: %{items: Enum.sort_by(state.items, fn item -> item end)}
    )

    defclient(join_numbers(state), do: %{joined: Enum.join(state.items, ",")})
  end

  test "tagged floats preserve type and negative zero through nested state" do
    state = %{value: -0.0, items: [%{amount: 1.0}]}
    assert LiveLift.State.validate!(state) == state
    tagged = FloatWire.encode(state)

    assert tagged == %{
             value: %{"$live_lift_float" => "-0.0"},
             items: [%{amount: %{"$live_lift_float" => "1.0"}}]
           }

    assert <<0x8000000000000000::unsigned-64>> = <<FloatWire.decode(tagged).value::float-64>>

    assert_raise ArgumentError, ~r/invalid LiveLift float tag/, fn ->
      FloatWire.decode(%{"$live_lift_float" => "1.0e+0"})
    end
  end

  test "seeded float text and bits match generated JavaScript" do
    samples =
      [-0.0, 0.0, 1.0, -1.0, 1.0e-5, 0.0001, 1000.0, 1.0e16, 5.0e-324, 1.7976931348623157e308] ++
        for(
          exponent <- -320..300//20,
          coefficient <- [1.1, -3.141592653589793, 9.87654321],
          do: coefficient * :math.pow(10, exponent)
        )

    bit_samples =
      StreamData.integer(0..0xFFEFFFFFFFFFFFFF)
      |> StreamData.seeded(20_261_114)
      |> Enum.take(5_000)
      |> Enum.reject(&(Bitwise.band(&1, 0x7FF0000000000000) == 0x7FF0000000000000))
      |> Enum.map(fn bits ->
        <<value::float-64>> = <<bits::unsigned-64>>
        value
      end)

    samples = samples ++ bit_samples

    samples = Enum.filter(samples, &is_float/1)

    expected =
      Enum.map(samples, fn value ->
        <<bits::unsigned-64>> = <<value::float-64>>
        <<round_trip_bits::unsigned-64>> = <<FloatWire.decode(FloatWire.encode(value))::float-64>>
        assert round_trip_bits == bits

        %{
          text: Float.to_string(value),
          bits: bits |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(16, "0")
        }
      end)

    input = Enum.map(samples, fn value -> FloatWire.encode(value) end)

    actual =
      run_node!(
        Compiler.compile_module(Actions) <>
          "\nconsole.log(JSON.stringify(#{Jason.encode!(input)}.map((item) => { const n = Number(item.$live_lift_float); const bytes = Buffer.allocUnsafe(8); bytes.writeDoubleBE(n); return {text: __liveLiftFloatText(n), bits: bytes.readBigUInt64BE().toString(16).padStart(16, '0')}; })));\n"
      )

    assert Jason.decode!(actual) == expected |> Jason.encode!() |> Jason.decode!()
  end

  test "mixed arithmetic, comparisons and nested equality match Elixir" do
    values = [-0.0, 0.0, 1.0, -1.25, 2.5, 1.0e-5, 1000.0, 1, -2, 7]

    cases =
      for left <- values, right <- values do
        %{left: left, right: right, items: [%{number: left}], other: [%{number: right}]}
      end

    expected = cases |> Enum.map(&Actions.calculate/1) |> FloatWire.encode()
    input = FloatWire.encode(cases)

    actual =
      run_node!(
        Compiler.compile_module(Actions) <>
          "\nconsole.log(JSON.stringify(#{Jason.encode!(input)}.map((state) => actions.calculate(state))));\n"
      )

    assert Jason.decode!(actual) == expected |> Jason.encode!() |> Jason.decode!()
  end

  test "sort_by preserves mixed numeric order and float wire types" do
    values = [
      -1.7976931348623157e308,
      -1.0,
      -0.0,
      0,
      0.0,
      5.0e-324,
      1,
      1.0,
      9_007_199_254_740_991,
      1.7976931348623157e308
    ]

    generated =
      StreamData.list_of(StreamData.member_of(values), max_length: 10)
      |> StreamData.seeded(20_261_115)
      |> Enum.take(300)

    cases = Enum.map([values, Enum.reverse(values) | generated], &%{items: &1})
    Enum.each(cases, &LiveLift.State.validate!/1)
    expected = cases |> Enum.map(&Actions.sort_numbers/1) |> FloatWire.encode()

    actual =
      run_node!(
        Compiler.compile_module(Actions) <>
          "\nconsole.log(JSON.stringify(#{cases |> FloatWire.encode() |> Jason.encode!()}.map((state) => actions.sort_numbers(state))));\n"
      )

    assert Jason.decode!(actual) == expected |> Jason.encode!() |> Jason.decode!()
  end

  test "join uses Elixir float text, including signed zero" do
    cases = [
      %{items: [-0.0, 0.0, 1.0, 1, 5.0e-324]},
      %{items: [1.7976931348623157e308, -1.0, 9_007_199_254_740_991]},
      %{items: []}
    ]

    expected = cases |> Enum.map(&Actions.join_numbers/1) |> FloatWire.encode()

    actual =
      run_node!(
        Compiler.compile_module(Actions) <>
          "\nconsole.log(JSON.stringify(#{cases |> FloatWire.encode() |> Jason.encode!()}.map((state) => actions.join_numbers(state))));\n"
      )

    assert Jason.decode!(actual) == expected |> Jason.encode!() |> Jason.decode!()
  end

  test "arithmetic overflow fails on both sides" do
    state = %{left: 1.0e308, right: 1.0e308, items: [], other: []}
    assert_raise ArithmeticError, fn -> Actions.calculate(state) end

    source =
      Compiler.compile_module(Actions) <>
        "\nactions.calculate(#{state |> FloatWire.encode() |> Jason.encode!()});\n"

    path = temp_path("mjs")

    try do
      File.write!(path, source)
      {output, status} = System.cmd("node", [path], stderr_to_stdout: true)
      assert status != 0
      assert output =~ "LiveLift expected a finite float"
    after
      File.rm(path)
    end
  end

  test "an unmarked server update advances the revision when float display changes" do
    for {before, after_value} <- [{-0.0, 0.0}, {1, 1.0}] do
      previous = %Phoenix.LiveView.Socket{assigns: %{value: before, __changed__: %{}}}
      next = %Phoenix.LiveView.Socket{assigns: %{value: after_value, __changed__: %{}}}

      assert {:noreply, updated} =
               LiveLift.Component.sync_unmarked({:noreply, next}, previous, [:value])

      assert updated.assigns.__live_lift_revision == 1
    end
  end

  test "server template renders float text and attributes with the tagged client tree" do
    tree = Template.compile(~s(<output title="{@value}">{@value}</output>), "float.ex")
    state = %{value: -0.0}

    assert tree |> Template.render_server(state) |> Phoenix.HTML.safe_to_string() ==
             ~s(<output title="-0.0" data-live-lift-bind-title="value"><!--live-lift:text-->-0.0<!--live-lift:end--></output>)

    case_data = %{
      tree: tree,
      state: FloatWire.encode(state),
      html: tree |> Template.render_server(state) |> Phoenix.HTML.safe_to_string()
    }

    path = temp_path("json")

    try do
      File.write!(path, Jason.encode!([case_data]))
      script = Path.expand("../../bench/template_parity.mjs", __DIR__)
      {output, 0} = System.cmd("node", [script, path], stderr_to_stdout: true)
      assert output =~ "1 template cases matched"
    after
      File.rm(path)
    end
  end

  defp run_node!(source) do
    path = temp_path("mjs")

    try do
      File.write!(path, source)
      {output, 0} = System.cmd("node", [path], stderr_to_stdout: true)
      output
    after
      File.rm(path)
    end
  end

  defp temp_path(extension) do
    Path.join(
      System.tmp_dir!(),
      "live_lift_float_#{System.unique_integer([:positive])}.#{extension}"
    )
  end
end
