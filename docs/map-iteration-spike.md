# Map iteration parity spike

Elixir maps do not guarantee enumeration order. A run on Elixir 1.20.2 and
OTP 29 showed that a 40-field atom-keyed map yielded keys in a different
order from JavaScript object enumeration for the same fields. Sorting values
after extraction does not always fix the issue. Elixir's stable sort can
retain the original order of values that compare equal, such as `1` and
`1.0`, even though the wire format preserves their distinct types.

Two forms have deterministic results for supported state maps:

- `Enum.count(Map.keys(map))`, `Enum.count(Map.values(map))`, and the same
  calls with `length/1` produce the number of fields.
- `map |> Map.keys() |> Enum.map(&Atom.to_string/1) |> Enum.sort()` produces
  sorted names. Safe state keys are ASCII, so sorting their names agrees
  across both runtimes.

Use an explicitly ordered list when the application needs an ordered sequence
of values. Bare projections produce a source-located compilation error.
The seeded parity corpus includes empty and small maps and a 40-field map.
