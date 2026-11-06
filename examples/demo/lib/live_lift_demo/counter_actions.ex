defmodule LiveLiftDemo.CounterActions do
  use LiveLift.Client

  defclient(advance(state), do: %{count: state.count + state.step, step: state.step})
  defclient(retreat(state), do: %{count: state.count - state.step, step: state.step})
end
