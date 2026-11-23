# Signed zero in unary plus

## Question

Why did the signed-zero parity test fail for both LiveView versions in
[Compatibility](https://github.com/Manuel1471/LiveLift/actions/runs/45111842270)?
The missing `linkedom` errors came from a separate setup step.

## Method

Compare ordinary Elixir functions with compiler-generated JavaScript, using
`Float.to_string/1` to distinguish the signs. One minimal probe is:

```elixir
defmodule UnaryPlusProbe do
  def dynamic(map), do: +map.value
  def signed_literal, do: +(-0.0)
  def folded_sum, do: +(-0.0 + -0.0)
end

IO.inspect({
  UnaryPlusProbe.dynamic(%{value: -0.0}),
  UnaryPlusProbe.signed_literal(),
  UnaryPlusProbe.folded_sum()
})
```

## Result

The failing GitHub runner used Elixir 1.18.6 and OTP 27 on Linux x86-64.
Its native dynamic unary plus returned positive zero. The generated
JavaScript preserved negative zero. A local x86-64 OTP 27 probe with
Elixir 1.18.6 returned `{0.0, 0.0, -0.0}`. An ARM64 OTP 27 container with
Elixir 1.18.4 returned `{-0.0, -0.0, -0.0}`.
The runtime instruction selection for x86-64 uses an addition
instruction for unary plus. See [the OTP 27 instruction table](https://github.com/erlang/otp/blob/OTP-27.3.4.19/erts/emulator/beam/jit/x86/ops.tab#L1241).

## Decision and limits

Probe a dynamic unary plus on the BEAM that generates the browser assets.
Use the existing JavaScript addition helper when that probe produces
positive zero. Preserve the result of recognized folded constant expressions
and check dynamic input, a signed literal, a literal sum and a literal
conditional against Elixir in the parity suite. The wire representation
continues to carry either sign.

The probe covers the documented compiler subset and the tested expression
forms. Build assets on the same BEAM target as the server when the sign of
zero matters to a handler.

## Verification

With Elixir 1.18.6, OTP 27.3.4.19, and Node 22.15.0, the full suite
passed on macOS x86-64 for LiveView 1.2.0 and 1.2.13, with 148 tests in
each run. The 34 browser runtime unit tests also passed. An x86-64 Linux
container ran the nine float and template parity tests with the compiled
LiveView 1.2.13 modules and passed. The container's full Mix build stopped
while loading the MIME dependency project.
