defmodule LiveLift.Client.Component do
  @moduledoc "A presentation component used inside a LiveLift client view."

  defmacro __using__(_opts) do
    quote do
      use LiveLift.Client

      @doc false
      def __live_lift_component__, do: true
    end
  end
end
