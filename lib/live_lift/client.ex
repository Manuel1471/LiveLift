defmodule LiveLift.Client do
  @moduledoc """
  Defines a client view in Elixir and compiles it for the browser.

  `client_template` holds validated HTML with bindings, keyed lists,
  conditions, and app-owned components. `defclient` defines normal Elixir
  functions as well as browser actions. Actions take state and optionally
  event data.

      defmodule ScoreView do
        use LiveLift.Client

        client_template "<button $click=\"advance\">Add</button><output>{@score}</output>"
        defclient advance(state), do: %{score: state.score + 1}
      end
  """

  defmacro __using__(_opts) do
    quote do
      import LiveLift.Client, only: [defclient: 2, client_template: 1]
      Module.register_attribute(__MODULE__, :live_lift_client_actions, accumulate: true)
      Module.register_attribute(__MODULE__, :live_lift_client_template, accumulate: false)
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

  defmacro defclient(
             {name, _,
              [{state, _, state_context} = state_arg, {event, _, event_context} = event_arg]},
             do: body
           )
           when is_atom(name) and is_atom(state) and is_atom(event) and
                  (is_atom(state_context) or is_nil(state_context)) and
                  (is_atom(event_context) or is_nil(event_context)) do
    LiveLift.Client.Compiler.compile_action(name, [state, event], body)

    quote do
      @live_lift_client_actions {unquote(name), [unquote(state), unquote(event)],
                                 unquote(Macro.escape(body))}
      def unquote(name)(unquote(state_arg), unquote(event_arg)), do: unquote(body)
    end
  end

  defmacro defclient(_head, do: _body) do
    raise ArgumentError, "defclient requires one state argument and an optional event argument"
  end

  defmacro client_template(source) when is_binary(source) do
    compiled_template = LiveLift.Template.compile(source, __CALLER__.file)

    quote do
      @live_lift_client_template unquote(Macro.escape(compiled_template))
    end
  end

  defmacro client_template(_source) do
    raise ArgumentError, "client_template requires a literal string"
  end

  defmacro __before_compile__(env) do
    actions = env.module |> Module.get_attribute(:live_lift_client_actions) |> Enum.reverse()
    template = Module.get_attribute(env.module, :live_lift_client_template)

    quote do
      @doc false
      def __live_lift_client_actions__, do: unquote(Macro.escape(actions))

      @doc false
      def __live_lift_client_template__, do: unquote(Macro.escape(template))
    end
  end
end
