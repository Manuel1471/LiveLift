defmodule LiveLift.State do
  @moduledoc "Validates values that may cross from Elixir into the browser."

  @max_safe_integer 9_007_199_254_740_991
  @max_list_length 10_000
  @max_map_fields 1_024
  @max_nodes 50_000
  @max_bytes 1_048_576
  @key ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/
  @reserved ~w(__proto__ constructor prototype)

  @spec validate!(map()) :: map()
  def validate!(state) when is_map(state) do
    validate_map!(state, [], 0, {0, 0})
    state
  end

  def validate!(_), do: raise(ArgumentError, "LiveLift state must be a map")

  defp validate_value!(value, path, _depth, budget) when is_binary(value) do
    unless String.valid?(value),
      do: raise(ArgumentError, "invalid UTF-8 in LiveLift state at #{format_path(path)}")

    charge!(budget, 1, byte_size(value), path)
  end

  defp validate_value!(value, path, _depth, budget) when is_boolean(value) or is_nil(value),
    do: charge!(budget, 1, 0, path)

  defp validate_value!(value, path, _depth, budget)
       when is_integer(value) and abs(value) <= @max_safe_integer,
       do: charge!(budget, 1, 0, path)

  defp validate_value!(value, path, _depth, budget) when is_float(value),
    do: charge!(budget, 1, byte_size(Float.to_string(value)) + 16, path)

  defp validate_value!(value, path, depth, budget) when is_list(value) and depth < 16 do
    if length(value) > @max_list_length,
      do: raise(ArgumentError, "LiveLift list length limit exceeded at #{format_path(path)}")

    validate_list!(value, path, depth + 1, charge!(budget, 1, 0, path), 0)
  end

  defp validate_value!(value, path, depth, budget) when is_map(value) and depth < 16,
    do: validate_map!(value, path, depth, budget)

  defp validate_value!(_value, path, _depth, _budget),
    do: raise(ArgumentError, "unsupported LiveLift state value at #{format_path(path)}")

  defp validate_map!(map, path, depth, budget) do
    if map_size(map) > @max_map_fields,
      do: raise(ArgumentError, "LiveLift map field limit exceeded at #{format_path(path)}")

    Enum.reduce(map, charge!(budget, 1, 0, path), fn {key, value}, acc ->
      key_string = if is_atom(key), do: Atom.to_string(key)

      unless key_string && Regex.match?(@key, key_string) && key_string not in @reserved do
        raise ArgumentError, "unsafe LiveLift state key at #{format_path(path)}: #{inspect(key)}"
      end

      acc = charge!(acc, 0, byte_size(key_string), path)
      validate_value!(value, [key_string | path], depth + 1, acc)
    end)
  end

  defp validate_list!([], _path, _depth, budget, _index), do: budget

  defp validate_list!([item | rest], path, depth, budget, index) do
    budget = validate_value!(item, [index | path], depth, budget)
    validate_list!(rest, path, depth, budget, index + 1)
  end

  defp format_path(path) do
    "state" <>
      (path
       |> Enum.reverse()
       |> Enum.map_join(fn
         index when is_integer(index) -> "[#{index}]"
         key -> "." <> key
       end))
  end

  defp charge!({nodes, bytes}, more_nodes, more_bytes, path) do
    next = {nodes + more_nodes, bytes + more_bytes}

    if elem(next, 0) > @max_nodes or elem(next, 1) > @max_bytes,
      do: raise(ArgumentError, "LiveLift state size limit exceeded at #{format_path(path)}")

    next
  end
end
