Mix.install([
  {:ecto, "3.14.2"},
  {:phoenix_ecto, "4.7.0"},
  {:phoenix_live_view, "1.2.13"}
])

alias Ecto.Changeset
alias Phoenix.Component
alias Phoenix.HTML.Form

build = fn data, params, action ->
  changeset =
    {data, %{name: :string, code: :string}}
    |> Changeset.cast(params, [:name, :code])
    |> Changeset.validate_required([:name, :code])
    |> Changeset.validate_length(:name, min: 2)
    |> Changeset.validate_format(:code, ~r/\A[A-Z]{2}\z/)

  form = Component.to_form(changeset, as: :profile, action: action)

  fields =
    for field <- [:name, :code], into: %{} do
      {field,
       %{
         value: Form.input_value(form, field),
         used: Component.used_input?(form[field]),
         errors: form[field].errors
       }}
    end

  %{valid: changeset.valid?, changes: changeset.changes, fields: fields}
end

blank = %{name: nil, code: nil}
saved = %{name: "Saved", code: "OK"}

for {label, data, params, action, expected} <- [
      {:initial, blank, %{}, nil, {false, {nil, false, []}, {nil, false, []}}},
      {:valid, blank, %{"name" => "é🙂", "code" => "OK"}, :validate,
       {true, {"é🙂", true, []}, {"OK", true, []}}},
      {:whitespace, blank, %{"name" => " \t", "code" => ""}, :validate,
       {false, {" \t", true, [:required]}, {"", true, [:required]}}},
      {:invalid, blank, %{"name" => "e\u0301", "code" => "bad"}, :validate,
       {false, {"e\u0301", true, [:length]}, {"bad", true, [:format]}}},
      {:unused, blank, %{"name" => "x", "_unused_name" => "", "code" => "OK"}, :validate,
       {false, {"x", false, [:length]}, {"OK", true, []}}},
      {:unchanged, saved, %{}, :validate, {true, {"Saved", false, []}, {"OK", false, []}}},
      {:cleared, saved, %{"name" => "", "code" => "OK"}, :validate,
       {false, {"", true, [:required]}, {"OK", true, []}}}
    ] do
  result = build.(data, params, action)

  observe = fn field ->
    %{value: value, used: used, errors: errors} = Map.fetch!(result.fields, field)
    {value, used, Enum.map(errors, fn {_message, opts} -> Keyword.fetch!(opts, :validation) end)}
  end

  actual = {result.valid, observe.(:name), observe.(:code)}

  unless actual == expected,
    do: raise("#{label}: expected #{inspect(expected)}, got #{inspect(actual)}")

  IO.inspect(result, label: Atom.to_string(label))
end
