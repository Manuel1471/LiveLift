defmodule LiveLift.FloatWire do
  @moduledoc "Internal tagged representation for finite Elixir floats at the browser boundary."

  @tag "$live_lift_float"

  @spec encode(term()) :: term()
  def encode(value) when is_float(value), do: %{@tag => Float.to_string(value)}
  def encode(value) when is_list(value), do: Enum.map(value, &encode/1)

  def encode(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, encode(item)} end)

  def encode(value), do: value

  @spec decode(term()) :: term()
  def decode(%{@tag => value} = tagged) when map_size(tagged) == 1 and is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} ->
        if value == Float.to_string(parsed),
          do: parsed,
          else: raise(ArgumentError, "invalid LiveLift float tag")

      _ ->
        raise ArgumentError, "invalid LiveLift float tag"
    end
  end

  def decode(value) when is_list(value), do: Enum.map(value, &decode/1)

  def decode(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, decode(item)} end)

  def decode(value), do: value
end
