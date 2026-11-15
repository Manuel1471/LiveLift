# `String.replace` parity spike

Elixir's `String.replace/3,4` accepts a binary pattern or a list of binary
patterns. A list containing an empty string raises; an empty list leaves the
input unchanged. Overlapping patterns choose the earliest and longest match:
both `["a", "ab"]` and `["ab", "a"]` replace `"ab"` with `"X"` as `"X"`.

The empty string pattern replaces at grapheme boundaries, including the two
outer boundaries: `String.replace("👨‍👩‍👧‍👦", "", "-")` returns
`"-👨‍👩‍👧‍👦-"`. With `global: false`, it replaces only the leading
boundary. The browser uses the existing `Intl.Segmenter` dependency. A
replacement string is literal: `$&` and `\0` are not interpolated.

Elixir accepts a one-argument callback returning iodata. The browser collects
UTF-8 bytes from strings and byte integers in nested lists, then decodes them
strictly. Invalid iodata or UTF-8 raises before updating client state.
The seeded parity corpus checks string and list patterns, empty patterns,
Unicode graphemes, `global: false`, callback results, and overlapping matches.
The native demo verifies a single replacement and server convergence in
Chromium, Firefox, and WebKit.

Regex patterns, dynamic options, and deprecated `insert_replaced` remain
server only. They fail to compile in a marked handler with a source location.
The `Intl.Segmenter` and Unicode-version dependency needs renewed checks in
the phase 7 compatibility gate.
