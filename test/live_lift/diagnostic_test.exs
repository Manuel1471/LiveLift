defmodule LiveLift.DiagnosticTest do
  use ExUnit.Case, async: true

  alias LiveLift.Template

  @moduletag :capture_log

  test "the native compiler reports the render definition when ~H is delegated" do
    source = """
    defmodule LiveLift.DiagnosticTest.Delegated do
      use Phoenix.LiveComponent
      use LiveLift

      def render(assigns), do: render_output(assigns)
      defp render_output(assigns), do: ~H"<output>{@count}</output>"

      @client true
      def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
    end
    """

    assert_diagnostic("delegated.ex", 5, "E060", "literal ~H template", fn ->
      Code.compile_string(source, "delegated.ex")
    end)
  end

  test "unmarked LiveView handlers can still use server functions rejected in marked handlers" do
    source = """
    defmodule LiveLift.DiagnosticTest.Server do
      use Phoenix.LiveComponent
      def render(assigns), do: ~H"<output>{@count}</output>"
      def handle_event("load", _params, socket) do
        {:noreply, assign(socket, :count, System.monotonic_time())}
      end
    end
    """

    assert [{__MODULE__.Server, _}] = Code.compile_string(source, "server.ex")

    marked =
      source
      |> String.replace(".Server", ".Client")
      |> String.replace("  def render", "  use LiveLift\n  def render")
      |> String.replace("  def handle_event", "  @client true\n  def handle_event")

    assert_diagnostic("client.ex", 6, "E056", "System.monotonic_time()", fn ->
      Code.compile_string(marked, "client.ex")
    end)
  end

  test "parameter and helper rejections identify their source" do
    for {code, line, reason, params, expression, helper} <- [
          {"E057", 6, "unsupported @client event parameter path", "params",
           ~s(params["constructor"]), ""},
          {"E058", 9, "has a guard", "_params", "limit(socket.assigns.count)",
           "defp limit(n) when is_integer(n), do: n"}
        ] do
      source = """
      defmodule LiveLift.DiagnosticTest.Invalid#{code} do
        use Phoenix.LiveComponent
        use LiveLift
        def render(assigns), do: ~H"<output>{@count}</output>"
        @client true
        def handle_event("run", #{params}, socket) do
          {:noreply, assign(socket, :count, #{expression})}
        end
        #{helper}
      end
      """

      assert_diagnostic("action.ex", line, code, reason, fn ->
        Code.compile_string(source, "action.ex")
      end)
    end
  end

  test "HEEx failures explain how to fix the offending part of the template" do
    for {code, reason, content, events} <- [
          {"E060", ":for requires id=", ~s(<li :for={item <- @items}>{item.name}</li>), []},
          {"E061", "unsupported client expression", "<p>{String.upcase(@name)}</p>", []},
          {"E062", "remote function component", "<Example.Badge.badge />", []},
          {"E063", "form has a checkbox",
           ~s(<form phx-change="save"><input type="checkbox" name="active" /></form>), ["save"]},
          {"E064", "unsafe client attribute: href", ~s(<a href="javascript:bad">Open</a>), []}
        ] do
      assert_diagnostic("markup.ex", 22, code, reason, fn ->
        Template.compile_liveview(
          "<section>\n" <> content <> "\n</section>",
          "markup.ex",
          events,
          %{},
          21
        )
      end)
    end
  end

  test "invalid HEEx has a source line and parser column with either parser" do
    assert_diagnostic("markup.ex", 22, "E065", "</span>", fn ->
      Template.compile_liveview("<section>\n<span></div>\n</section>", "markup.ex", [], %{}, 21)
    end)
  end

  defp assert_diagnostic(file, line, code, detail, compile) do
    error = assert_raise ArgumentError, compile
    [problem, next_step] = String.split(Exception.message(error), "\n  ", parts: 2)
    assert problem =~ ~r/^#{Regex.escape(file)}:#{line}(?::\d+)?: /
    assert problem =~ detail
    assert problem =~ "(#{code})"
    assert next_step =~ ~r/^(Use|Fix|Remove) /
    assert next_step =~ "See docs/errors/#{code}.md"
  end
end
