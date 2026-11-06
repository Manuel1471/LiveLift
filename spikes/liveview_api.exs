# Run with: mix run spikes/liveview_api.exs
# A compile-time feasibility test. This does not add a public LiveLift API.
require Phoenix.LiveViewTest

defmodule LiveLiftSpike.Capture do
  defmacro __using__(_) do
    quote do
      use Phoenix.LiveComponent
      Module.register_attribute(__MODULE__, :client, persist: false)
      Module.register_attribute(__MODULE__, :captured, accumulate: true)
      @on_definition {LiveLiftSpike.Capture, :on_definition}
      @before_compile LiveLiftSpike.Capture
    end
  end

  def on_definition(env, :def, name, args, _guards, body) when name in [:render, :handle_event] do
    Module.put_attribute(env.module, :captured, {name, length(args), Module.get_attribute(env.module, :client), body})
    Module.delete_attribute(env.module, :client)
  end

  def on_definition(_, _, _, _, _, _), do: :ok

  defmacro __before_compile__(env) do
    captured = env.module |> Module.get_attribute(:captured) |> Enum.reverse()
    quote do
      def __captured__, do: unquote(Macro.escape(captured))
    end
  end
end

defmodule LiveLiftSpike.Counter do
  use LiveLiftSpike.Capture

  def render(assigns) do
    ~H"""
    <button phx-click="inc" phx-target={@myself}>{@count}</button>
    """
  end

  @client true
  def handle_event("inc", _, socket), do: {:noreply, socket}
  def handle_event("server", _, socket), do: {:noreply, socket}
end

captured = LiveLiftSpike.Counter.__captured__()
{_, _, _, render_body} = Enum.find(captured, fn {name, _, _, _} -> name == :render end)
unless match?([do: {:sigil_H, _, _}], render_body), do: raise("S1: ~H source was not captured")
marked = for {:handle_event, 3, true, body} <- captured, do: body
unless length(marked) == 1, do: raise("S1: @client leaked to another handler")
IO.puts("S1 passed: @on_definition captured ~H and one marked handler")

defmodule LiveLiftSpike.Boundary do
  defmacro __using__(_) do
    quote do
      use Phoenix.LiveComponent
      @before_compile LiveLiftSpike.Boundary
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      defoverridable render: 1

      def render(var!(assigns)) do
        inner = super(var!(assigns))
        var!(assigns) = Phoenix.Component.assign(var!(assigns), :inner, inner)

        ~H"""
        <div id={@id} phx-hook="LiveLift" phx-update="ignore">{@inner}</div>
        """
      end
    end
  end
end

defmodule LiveLiftSpike.WrappedComponent do
  use LiveLiftSpike.Boundary

  def render(assigns) do
    ~H"<button>{@count}</button>"
  end
end

defmodule LiveLiftSpike.RenderCheck do
  import Phoenix.LiveViewTest, only: [render_component: 2]
  def run, do: render_component(&LiveLiftSpike.WrappedComponent.render/1, id: "spike", count: 3)
end

html = LiveLiftSpike.RenderCheck.run()
unless html =~ ~s(phx-update="ignore") and html =~ ~s(<button>3</button>),
  do: raise("S2: generated boundary did not render")
IO.puts("S2 passed: wrapper surrounds the original ~H render")

defmodule LiveLiftSpike.EventWrapper do
  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :client, persist: false)
      Module.register_attribute(__MODULE__, :client_events, accumulate: true)
      @on_definition {LiveLiftSpike.EventWrapper, :on_definition}
      @before_compile LiveLiftSpike.EventWrapper
    end
  end

  def on_definition(env, :def, :handle_event, [event | _], _guards, _body) do
    if Module.get_attribute(env.module, :client) == true and is_binary(event),
      do: Module.put_attribute(env.module, :client_events, event)

    Module.delete_attribute(env.module, :client)
  end

  def on_definition(_, _, _, _, _, _), do: :ok

  defmacro __before_compile__(env) do
    events = Module.get_attribute(env.module, :client_events) |> Enum.uniq()

    quote do
      defoverridable handle_event: 3

      def handle_event(event, params, socket) do
        result = super(event, params, socket)
        if event in unquote(events), do: {:client_intercepted, result}, else: result
      end
    end
  end
end

defmodule LiveLiftSpike.Events do
  use Phoenix.LiveComponent
  use LiveLiftSpike.EventWrapper

  @client true
  def handle_event("inc", _, socket), do: {:noreply, socket + 1}
  def handle_event("server", _, socket), do: {:noreply, socket + 10}
  def render(assigns), do: ~H"<div>test</div>"
end

unless LiveLiftSpike.Events.handle_event("inc", %{}, 1) == {:client_intercepted, {:noreply, 2}},
  do: raise("S3: marked handler was not intercepted")

unless LiveLiftSpike.Events.handle_event("server", %{}, 1) == {:noreply, 11},
  do: raise("S3: unmarked handler changed")

socket = %Phoenix.LiveView.Socket{}
socket = Phoenix.LiveView.push_event(socket, "live_lift:patch", %{id: "spike"})
unless socket.private.live_temp.push_events == [["live_lift:patch", %{id: "spike"}]],
  do: raise("S3: public push_event did not queue a response")

IO.puts("S3 passed: marked handler can be wrapped; public push_event queues a response")

# S4 keeps the actual render and event source identical. Only the opt-in use
# line and one attribute differ. This is a migration surface check, not yet a
# browser execution test.
defmodule LiveLiftSpike.OptIn do
  defmacro __using__(_) do
    quote do
      use Phoenix.LiveComponent
      Module.register_attribute(__MODULE__, :client, persist: false)
      Module.register_attribute(__MODULE__, :captured, accumulate: true)
      @on_definition {LiveLiftSpike.Capture, :on_definition}
      @before_compile LiveLiftSpike.Capture
      @before_compile LiveLiftSpike.Boundary
    end
  end
end

shared_source = ~S'''
  def render(assigns) do
    ~H"""
    <button phx-click="inc" phx-target={@myself}>{@count}</button>
    """
  end

  def handle_event("inc", _params, socket), do: {:noreply, socket}
'''

plain_source = """
defmodule LiveLiftSpike.PlainCounter do
  use Phoenix.LiveComponent
#{shared_source}
end
"""

opted_source =
  plain_source
  |> String.replace("LiveLiftSpike.PlainCounter", "LiveLiftSpike.OptedCounter")
  |> String.replace("use Phoenix.LiveComponent", "use LiveLiftSpike.OptIn")
  |> String.replace("  def handle_event", "  @client true\n  def handle_event")

Code.compile_string(plain_source, "plain_counter.ex")
Code.compile_string(opted_source, "opted_counter.ex")

defmodule LiveLiftSpike.MigrationRenderCheck do
  import Phoenix.LiveViewTest, only: [render_component: 2]

  def plain do
    render_component(&LiveLiftSpike.PlainCounter.render/1,
      id: "migration-spike",
      count: 3,
      myself: %Phoenix.LiveComponent.CID{cid: 1}
    )
  end

  def opted do
    render_component(&LiveLiftSpike.OptedCounter.render/1,
      id: "migration-spike",
      count: 3,
      myself: %Phoenix.LiveComponent.CID{cid: 1}
    )
  end
end

plain_html = LiveLiftSpike.MigrationRenderCheck.plain()
opted_html = LiveLiftSpike.MigrationRenderCheck.opted()

unless plain_html =~ ~s(phx-click="inc") and opted_html =~ ~s(phx-click="inc") and
         plain_html =~ ">3</button>" and opted_html =~ ">3</button>" and
         opted_html =~ ~s(phx-update="ignore"),
  do: raise("S4: opt-in changed the original HEEx or failed to create the boundary")

captured = LiveLiftSpike.OptedCounter.__captured__()
unless Enum.count(captured, fn {name, _, marked, _} -> name == :handle_event and marked == true end) == 1,
  do: raise("S4: the two-line opt-in did not mark exactly one handler")

IO.puts("S4 passed: unchanged HEEx and handler compile with only use + @client changed")
