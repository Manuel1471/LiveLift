defmodule LiveLift.Client do
  @moduledoc """
  Defines a small, pure Elixir function that LiveLift can compile for the browser.

  `defclient` also defines a normal Elixir function, so its behavior can be
  exercised on the server. Currently one argument, safe integer literals,
  `+`, `-`, `*`, atom-keyed map literals, and field reads are supported.

      defmodule CounterActions do
        use LiveLift.Client

        defclient increment(count), do: count + 1
      end
  """

  defmacro __using__(_opts) do
    quote do
      import LiveLift.Client, only: [defclient: 2]
      Module.register_attribute(__MODULE__, :live_lift_client_actions, accumulate: true)
      @before_compile LiveLift.Client
    end
  end

  defmacro defclient({name, _, [{arg, _, context} = argument]}, do: body)
           when is_atom(name) and is_atom(arg) and (is_atom(context) or is_nil(context)) do
    LiveLift.Client.Compiler.compile_action(name, arg, body)

    quote do
      @live_lift_client_actions {unquote(name), unquote(arg), unquote(Macro.escape(body))}
      def unquote(name)(unquote(argument)), do: unquote(body)
    end
  end

  defmacro defclient(_head, do: _body) do
    raise ArgumentError, "defclient requires a named function with one variable argument"
  end

  defmacro __before_compile__(env) do
    actions = env.module |> Module.get_attribute(:live_lift_client_actions) |> Enum.reverse()

    quote do
      @doc false
      def __live_lift_client_actions__, do: unquote(Macro.escape(actions))
    end
  end
end
