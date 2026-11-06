defmodule LiveLift.Client do
  @moduledoc """
  Defines a client view in Elixir and compiles it for the browser.

  `client_template` holds static HTML with text bindings and click actions.
  `defclient` defines normal Elixir functions as well as browser actions.
  Currently the expression compiler supports one argument, safe integer
  literals, `+`, `-`, `*`, atom-keyed map literals, and field reads.

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

  defmacro defclient(_head, do: _body) do
    raise ArgumentError, "defclient requires a named function with one variable argument"
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
