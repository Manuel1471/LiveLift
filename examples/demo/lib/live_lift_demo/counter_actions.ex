defmodule LiveLiftDemo.CounterActions do
  use LiveLift.Client

  defclient(increment(count), do: count + 1)
  defclient(decrement(count), do: count - 1)
end
