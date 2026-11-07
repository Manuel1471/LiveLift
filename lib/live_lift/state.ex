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
    validate_map!(state, "state", 0, {0, 0})
    state
  end

  def validate!(_), do: raise(ArgumentError, "LiveLift state must be a map")

  defp validate_value!(value, path, _depth, budget) when is_binary(value) do
    unless String.valid?(value),
      do: raise(ArgumentError, "invalid UTF-8 in LiveLift state at #{path}")

    charge!(budget, 1, byte_size(value), path)
  end

  defp validate_value!(value, path, _depth, budget) when is_boolean(value) or is_nil(value),
    do: charge!(budget, 1, 0, path)

  defp validate_value!(value, path, _depth, budget)
       when is_integer(value) and abs(value) <= @max_safe_integer,
       do: charge!(budget, 1, 0, path)

  defp validate_value!(value, path, depth, budget) when is_list(value) and depth < 16 do
    if length(value) > @max_list_length,
      do: raise(ArgumentError, "LiveLift list length limit exceeded at #{path}")

    value
    |> Enum.with_index()
    |> Enum.reduce(charge!(budget, 1, 0, path), fn {item, index}, acc ->
      validate_value!(item, "#{path}[#{index}]", depth + 1, acc)
    end)
  end

  defp validate_value!(value, path, depth, budget) when is_map(value) and depth < 16,
    do: validate_map!(value, path, depth, budget)

  defp validate_value!(_value, path, _depth, _budget),
    do: raise(ArgumentError, "unsupported LiveLift state value at #{path}")

  defp validate_map!(map, path, depth, budget) do
    if map_size(map) > @max_map_fields,
      do: raise(ArgumentError, "LiveLift map field limit exceeded at #{path}")

    Enum.reduce(map, charge!(budget, 1, 0, path), fn {key, value}, acc ->
      unless is_atom(key) and Regex.match?(@key, Atom.to_string(key)) and
               Atom.to_string(key) not in @reserved do
        raise ArgumentError, "unsafe LiveLift state key at #{path}: #{inspect(key)}"
      end

      acc = charge!(acc, 0, byte_size(Atom.to_string(key)), path)
      validate_value!(value, "#{path}.#{key}", depth + 1, acc)
    end)
  end

  defp charge!({nodes, bytes}, more_nodes, more_bytes, path) do
    next = {nodes + more_nodes, bytes + more_bytes}

    if elem(next, 0) > @max_nodes or elem(next, 1) > @max_bytes,
      do: raise(ArgumentError, "LiveLift state size limit exceeded at #{path}")

    next
  end
end
