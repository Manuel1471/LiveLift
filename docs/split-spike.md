# `String.split` parity spike

JavaScript's `split("")` separates UTF-16 code units. Elixir splits on
grapheme boundaries and includes leading and trailing empty strings before
`trim: true` is applied. For example, Elixir returns
`["", "👨‍👩‍👧‍👦", ""]` for `String.split("👨‍👩‍👧‍👦", "")`.
The client uses `Intl.Segmenter` for this case, matching the existing
`String.length/1` dependency.

We scanned all 1,112,064 Unicode scalar values on Elixir 1.20.2 / OTP 29
to find which characters `String.split/1` treats as whitespace between two
letters. It matched exactly 22 values: U+0009–U+000D, U+0020, U+0085,
U+1680, U+2000–U+2006, U+2008–U+200A, U+2028, U+2029, U+205F, and U+3000.
U+00A0, U+2007, U+202F, and U+FEFF do not split, even though some are
trimmed by `String.trim/1` or JavaScript's `trim()`.

For a list of separators, Elixir chooses the earliest match and the longest
separator when matches start at the same position: both `["a", "ab"]` and
`["ab", "a"]` split `"ab"` into `["", ""]`. `parts: n` leaves the
unprocessed remainder as the final part; `trim: true` skips empty parts when
counting. The seeded Elixir/JavaScript corpus covers these cases, empty
strings, Unicode graphemes, literal `trim`/`parts` options, and dynamic
string or string-list patterns. The native demo verifies split and server
convergence in Chromium, Firefox, and WebKit.

Regex patterns and dynamic options remain server only. `Intl.Segmenter` and
Elixir's Unicode tables need renewed parity checks in the phase 7
compatibility gate.
