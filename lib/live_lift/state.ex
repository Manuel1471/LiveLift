defmodule LiveLift.State do
  @moduledoc "Validates values that may cross from Elixir into the browser."

  @max_safe_integer 9_007_199_254_740_991
  @key ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/
  @reserved ~w(__proto__ constructor prototype)

  @spec validate!(map()) :: map()
  def validate!(state) when is_map(state) do
    validate_map!(state, "state", 0)
    state
  end

  def validate!(_), do: raise(ArgumentError, "LiveLift state must be a map")

  defp validate_value!(value, _path, _depth)
       when is_binary(value) or is_boolean(value) or is_nil(value), do: :ok

  defp validate_value!(value, _path, _depth)
       when is_integer(value) and abs(value) <= @max_safe_integer, do: :ok

  defp validate_value!(value, path, depth) when is_list(value) and depth < 16 do
    value
    |> Enum.with_index()
    |> Enum.each(fn {item, index} -> validate_value!(item, "#{path}[#{index}]", depth + 1) end)
  end

  defp validate_value!(value, path, depth) when is_map(value) and depth < 16,
    do: validate_map!(value, path, depth)

  defp validate_value!(_value, path, _depth),
    do: raise(ArgumentError, "unsupported LiveLift state value at #{path}")

  defp validate_map!(map, path, depth) do
    Enum.each(map, fn {key, value} ->
      unless is_atom(key) and Regex.match?(@key, Atom.to_string(key)) and
               Atom.to_string(key) not in @reserved do
        raise ArgumentError, "unsafe LiveLift state key at #{path}: #{inspect(key)}"
      end

      validate_value!(value, "#{path}.#{key}", depth + 1)
    end)
  end
end
