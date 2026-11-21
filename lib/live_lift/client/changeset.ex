defmodule LiveLift.Client.Changeset do
  @moduledoc false

  @field ~r/\A[A-Za-z_][A-Za-z0-9_]*\z/
  @reserved ~w(__proto__ prototype constructor)
  @token ~r/(?:[A-Za-z0-9_@:%-]|\\[.+]|\[(?:[A-Za-z0-9](?:-[A-Za-z0-9])?|[_.+])+-?\])(?<repeat>\{[1-9][0-9]?\}|[+?])?/

  def expression!(source, projection, compile) do
    {data, params, fields, rules} = parse!(source, [])
    validate_projection!(projection, fields)

    "__liveLiftChangeset(#{compile.(data)}, #{compile.(params)}, #{Jason.encode!(fields)}, " <>
      "#{Jason.encode!(rules)}, #{Jason.encode!(projection)})"
  end

  def form!(
        {{:., _, [{:__aliases__, _, [:Phoenix, :Component]}, :to_form]}, _, [source | args]},
        projection
      ) do
    options =
      case args do
        [] -> []
        [options] when is_list(options) -> options
        _ -> unsupported_form!("to_form/2 requires literal options")
      end

    unless Keyword.keyword?(options) and Enum.all?(options, &form_option?/1) and
             length(options) == map_size(Map.new(options)) do
      unsupported_form!("to_form/2 supports literal :action, :as and :id options")
    end

    {source, projection ++ [Keyword.get(options, :action) not in [nil, :ignore]]}
  end

  def form!(_, _), do: unsupported_form!("use Phoenix.Component.to_form/2 on a client changeset")

  defp form_option?({:action, action}), do: is_atom(action)
  defp form_option?({:as, as}), do: is_atom(as) or is_binary(as)
  defp form_option?({:id, id}), do: is_binary(id)
  defp form_option?(_), do: false

  defp parse!(
         {{:., _, [{:__aliases__, _, [:Ecto, :Changeset]}, :cast]}, _,
          [{data, {:%{}, _, types}}, params, fields]},
         rules
       )
       when is_list(types) do
    fields = fields!(fields)

    unless Keyword.keyword?(types) and Enum.all?(fields, &(Keyword.get(types, &1) == :string)) and
             Enum.all?(types, fn {_, type} -> type == :string end) do
      unsupported!("cast/3 requires literal :string field types")
    end

    for [_operation, fields_or_field | _] <- rules, field <- List.wrap(fields_or_field) do
      unless field in fields,
        do: unsupported!("validators must refer to fields selected by cast/3")
    end

    {data, params, fields, rules}
  end

  defp parse!(
         {{:., _, [{:__aliases__, _, [:Ecto, :Changeset]}, name]}, _, [source | args]},
         rules
       )
       when name in [:validate_required, :validate_length, :validate_format] do
    parse!(source, [rule!(name, args) | rules])
  end

  defp parse!(_, _),
    do: unsupported!("use a piped Ecto.Changeset.cast/3 with schemaless string fields")

  defp rule!(:validate_required, [fields]), do: ["required", fields!(List.wrap(fields))]
  defp rule!(:validate_required, [fields, []]), do: rule!(:validate_required, [fields])

  defp rule!(:validate_length, [field, options]) when is_list(options) do
    if options == [] or
         not Enum.all?(options, fn
           {key, count} when key in [:min, :max, :is] -> is_integer(count) and count in 0..65_536
           _ -> false
         end) or (Keyword.has_key?(options, :is) and length(options) != 1) do
      unsupported!("validate_length/3 needs literal grapheme bounds using :min, :max or :is")
    end

    if length(Keyword.keys(options)) != map_size(Map.new(options)) do
      unsupported!("validate_length/3 requires unique options")
    end

    ["length", field!(field), Map.new(options)]
  end

  defp rule!(:validate_format, [field, pattern]), do: ["format", field!(field), format!(pattern)]

  defp rule!(:validate_format, [field, pattern, []]),
    do: rule!(:validate_format, [field, pattern])

  defp rule!(name, _args),
    do: unsupported!("#{name} requires literal fields and supported options")

  defp format!({:sigil_r, _, [{:<<>>, _, [source]}, []]}) when is_binary(source) do
    {body, end_anchor} =
      cond do
        String.starts_with?(source, "\\A") and String.ends_with?(source, "\\z") ->
          {binary_part(source, 2, byte_size(source) - 4), "$"}

        String.starts_with?(source, "^") and String.ends_with?(source, "$") and
            byte_size(source) >= 2 ->
          {binary_part(source, 1, byte_size(source) - 2), "(?:\\n)?$"}

        true ->
          invalid_format!()
      end

    if body == "" or byte_size(body) > 128, do: invalid_format!()

    tokens = Regex.scan(@token, body)

    if Enum.map_join(tokens, &hd/1) != body or
         Enum.count(tokens, fn [_ | captures] -> captures in [["+"], ["?"]] end) > 1 or
         not match?({:ok, _}, Regex.compile(source)) do
      invalid_format!()
    end

    "^" <> body <> end_anchor
  end

  defp format!(_), do: invalid_format!()

  defp invalid_format! do
    unsupported!(
      "validate_format/4 requires an anchored literal ~r with ASCII tokens, no flags and at most one variable repeat"
    )
  end

  defp fields!(fields) when is_list(fields) and length(fields) in 1..32 do
    if Enum.uniq(fields) != fields, do: unsupported!("field lists must contain distinct atoms")
    Enum.map(fields, &field!/1)
  end

  defp fields!(_), do: unsupported!("use a literal list of 1 to 32 field atoms")

  defp field!(field) when is_atom(field) do
    name = Atom.to_string(field)

    if Regex.match?(@field, name) and name not in @reserved,
      do: field,
      else: unsupported!("unsafe field name")
  end

  defp field!(_), do: unsupported!("use a literal field atom")

  defp validate_projection!(:valid, _fields), do: :ok

  defp validate_projection!([:field, field], fields) do
    unless field in fields, do: unsupported!("get_field/2 must refer to a cast field")
  end

  defp validate_projection!([kind, field, _show_errors], fields)
       when kind in [:input, :used, :errors] do
    unless field in fields, do: unsupported_form!("form field must be selected by cast/3")
  end

  defp unsupported!(reason), do: raise(ArgumentError, "unsupported client changeset: #{reason}")

  defp unsupported_form!(reason),
    do:
      raise(ArgumentError,
        message: "unsupported client changeset form (E052): #{reason}. See docs/errors/E052.md"
      )
end
