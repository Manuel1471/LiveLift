# Changeset form spike

Run `elixir bench/changeset_form_spike.exs` from the repository root. It uses
Ecto 3.14.2, Phoenix Ecto 4.7.0, and LiveView 1.2.13 through `Mix.install/1`.
The app and library keep their existing dependencies.

The probe casts two string fields, applies `validate_required/3`,
`validate_length/3`, and `validate_format/4`, and reads the fields through
Phoenix's `to_form/2`. Its seven assertions show the behavior a browser
projection must reproduce.

| Form case | Result |
|---|---|
| Initial render | The changeset is invalid, fields are unused, and the form exposes no errors while its action is `nil`. |
| Valid Unicode | Two graphemes satisfy `min: 2` and the form displays both as entered. |
| Whitespace | Ecto removes the changes and reports required errors. The form still displays the raw whitespace. |
| Invalid length and format | A decomposed accented letter counts as one grapheme. The invalid code is displayed as entered, with a separate format error. |
| Unused input | The field carries an error and `used_input?/1` is false. The view can use this signal to decide whether to show feedback. |
| Existing data | A missing parameter displays the existing value and can pass required validation. |
| Clearing a saved value | The form shows the empty submitted value alongside its required error. |

The supported client representation needs separate values for the submitted
field, the cast change, and the value displayed by Phoenix. It also needs
the action and whether each field was used. Keep error messages and their
metadata until the app formats them, including the length count. This gives
the browser a bounded projection and leaves the original changeset on the
server. For the first format cases, verify a literal regex subset against
both runtimes before accepting it in the compiler.

Phoenix represents unused fields with `_unused_<field>` metadata. A plain
`FormData` read lacks this metadata. The generated serializer now decorates
the ordinary parameters of forms that use `used_input?/1` and shares the same
payload with the prediction and the server event.

[Ecto changeset API](https://ecto.hexdocs.pm/3.14.2/Ecto.Changeset.html)
and [Phoenix form API](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html#to_form/2).
