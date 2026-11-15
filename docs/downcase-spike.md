# `String.downcase/1` Unicode spike

Elixir lowercases each Unicode character without the context-sensitive final
sigma rule. On this toolchain, `String.downcase("ΟΣ")` returns `"οσ"`; JavaScript
`"ΟΣ".toLowerCase()` returns `"ος"`. Lowercasing one code point at a time with
`Array.from(text, character => character.toLowerCase()).join("")` returns
Elixir's result for this case.

We compared all 1,112,064 Unicode scalar values (excluding surrogates) on
Elixir 1.20.2 / OTP 29 against Node 26.5.0. Elixir changed 1,488 scalar
values; per-character JavaScript lowercasing had **zero differences** across
the full scan. The seeded language corpus additionally compares 1,000 mixed
strings, including Greek sigma, dotted I, sharp S, combining marks, and emoji.
The native demo verifies the final-sigma case and server convergence in
Chromium, Firefox, and WebKit.

This result establishes parity on the tested Unicode tables. Browser and
Elixir Unicode versions can change; the phase 7 compatibility gate must
repeat this comparison for supported toolchains. Locale-specific
`String.downcase/2` remains server only.
