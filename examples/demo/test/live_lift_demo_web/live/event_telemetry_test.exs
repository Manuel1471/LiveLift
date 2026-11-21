defmodule LiveLiftDemoWeb.EventTelemetryTest do
  use LiveLiftDemoWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias LiveLiftDemoWeb.{NativeCounterComponent, NativeCounterServerComponent, NativeTimerLive}

  @component_stop [:phoenix, :live_component, :handle_event, :stop]
  @view_stop [:phoenix, :live_view, :handle_event, :stop]
  @lift_event [:live_lift, :component, :event]

  test "counts native events before and after opt-in using Phoenix metadata", %{conn: conn} do
    attach([@component_stop, @view_stop, @lift_event])
    {:ok, server, _html} = live(recycle(conn), "/native-counter-server")
    {:ok, client, _html} = live(recycle(conn), "/native-counter")
    {:ok, root, _html} = live(recycle(conn), "/native-timer")

    for _ <- 1..2 do
      server |> element("button", "Add one") |> render_click()

      assert_receive {@component_stop, NativeCounterServerComponent, "inc", elapsed}
      assert is_integer(elapsed) and elapsed >= 0
    end

    refute_received {@lift_event, NativeCounterServerComponent, _, _}

    client |> element("button", "Add one") |> render_click()
    assert_receive {@component_stop, NativeCounterComponent, "inc", phoenix_elapsed}
    assert_receive {@lift_event, NativeCounterComponent, "inc", lift_elapsed}
    assert phoenix_elapsed >= lift_elapsed and lift_elapsed >= 0

    root |> element("button", "Add one") |> render_click()
    assert_receive {@view_stop, NativeTimerLive, "inc", root_elapsed}
    assert is_integer(root_elapsed) and root_elapsed >= 0
  end

  if System.get_env("LIVE_LIFT_BENCH") == "1" do
    @tag :telemetry_benchmark
    test "measures the same Phoenix component span for both routes", %{conn: conn} do
      attach([@component_stop])
      {:ok, server, _html} = live(recycle(conn), "/native-counter-server")
      {:ok, client, _html} = live(recycle(conn), "/native-counter")

      samples = 100
      warmups = 20

      variants = [
        {:server, NativeCounterServerComponent, server},
        {:optimistic, NativeCounterComponent, client}
      ]

      observations =
        for index <- 1..(samples + warmups),
            {mode, module, view} <- order(variants, index),
            params = if(mode == :optimistic, do: %{"_live_lift_seq" => index}, else: %{}),
            elapsed = increment(view, module, params),
            index > warmups,
            reduce: %{server: [], optimistic: []} do
          readings -> Map.update!(readings, mode, &[elapsed | &1])
        end

      assert Enum.all?(observations, fn {_mode, values} -> length(values) == samples end)

      assert has_element?(
               client,
               ~s(#native-counter[data-live-lift-ack-seq="#{samples + warmups}"])
             )

      assert has_element?(server, "output", Integer.to_string(samples + warmups))

      IO.puts(
        Jason.encode!(%{
          samples_per_variant: samples,
          warmups_per_variant: warmups,
          server_us: summarize(observations.server),
          optimistic_us: summarize(observations.optimistic)
        })
      )
    end

    defp order(variants, index) when rem(index, 2) == 0, do: Enum.reverse(variants)
    defp order(variants, _index), do: variants

    defp increment(view, module, params) do
      view |> element("button", "Add one") |> render_click(params)
      assert_receive {@component_stop, ^module, "inc", elapsed}
      System.convert_time_unit(elapsed, :native, :nanosecond) / 1_000
    end

    defp summarize(values) do
      sorted = Enum.sort(values)
      percentile = fn fraction -> Enum.at(sorted, ceil(length(sorted) * fraction) - 1) end

      %{
        min: hd(sorted),
        median: percentile.(0.5),
        p95: percentile.(0.95),
        max: List.last(sorted),
        iqr: percentile.(0.75) - percentile.(0.25)
      }
    end
  end

  defp attach(events) do
    id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach_many(id, events, &__MODULE__.capture/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
  end

  @doc false
  def capture(
        @view_stop = name,
        %{duration: duration},
        %{socket: %{view: view}, event: event},
        pid
      ),
      do: send(pid, {name, view, event, duration})

  def capture(name, %{duration: duration}, %{component: module, event: event}, pid),
    do: send(pid, {name, module, event, duration})
end
