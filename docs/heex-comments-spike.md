# HEEx comments spike

## Question

Can both LiveLift parser paths keep ordinary server-side HEEx comments
without changing the visible output or diagnostics?

## Method

On baseline `243c703`, use `mix run` to compare
`LiveLift.Template.Parser.parse_with!/4`, Phoenix's parser with
`strip_eex_comments: true`, and `EEx.tokenize/2`. Run with
LiveView 1.2.15, Elixir 1.20.2 and OTP 29.0.3. Inspect the option
in the local LiveView 1.2.0 package as well.

## Result

LiveLift rejected a comment in normal text through both paths. An
unterminated comment exposed the native parser's internal match error.
Phoenix can strip the comment with an existing option on both supported
versions. A removed comment can leave two adjacent text tokens, including
the two halves of an HTML comment. The fallback must consume the original
source position without emitting the server-side comment.

## Decision

Use Phoenix's stripping option and join adjacent text tokens. In the
fallback, consume comments in text, including inside an HTML comment.
Verify the same DOM from Phoenix and LiveLift, exact source coordinates
after multiline comments, and an actionable `E065` for an unclosed
comment. Comments inside tags and braced expressions remain invalid;
general EEx expressions are outside this delivery.
