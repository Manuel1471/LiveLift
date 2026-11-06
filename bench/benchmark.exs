defmodule LiveLift.BenchView do
  use LiveLift.Client

  client_template("<ul><li :for={item <- @items} :key={item.id}>{@item.name}</li></ul>")
  defclient(increment(state), do: %{count: state.count + 1})
end

defmodule LiveLift.Benchmark do
  def run do
    template = LiveLift.BenchView.__live_lift_client_template__()

    render =
      for size <- [10, 100, 1_000], into: %{} do
        state = %{items: for(id <- 1..size, do: %{id: id, name: "Task #{id}"})}
        samples = sample(fn -> LiveLift.Template.render_server(template, state) end, 100)
        {size, stats(samples)}
      end

    elixir_action = sample(fn -> LiveLift.BenchView.increment(%{count: 1}) end, 10_000)
    javascript = LiveLift.Client.Compiler.compile_module(LiveLift.BenchView)

    node_source =
      javascript <>
        """
        const times = [];
        for (let i = 0; i < 10000; i++) {
          const start = performance.now();
          actions.increment({count: i});
          times.push((performance.now() - start) * 1000);
        }
        times.sort((a, b) => a - b);
        console.log(JSON.stringify({median_us: times[5000], p95_us: times[9500]}));
        """

    {node_output, 0} = System.cmd("node", ["--input-type=module", "--eval", node_source])

    result = %{
      elixir: System.version(),
      otp: :erlang.system_info(:otp_release) |> List.to_string(),
      node: System.cmd("node", ["--version"]) |> elem(0) |> String.trim(),
      render_server_us: render,
      action_elixir_us: stats(elixir_action),
      action_javascript_us: Jason.decode!(node_output),
      samples: %{render: 100, action: 10_000}
    }

    IO.puts(Jason.encode!(result, pretty: true))
  end

  defp sample(fun, count) do
    fun.()

    for _ <- 1..count do
      start = System.monotonic_time(:nanosecond)
      fun.()
      (System.monotonic_time(:nanosecond) - start) / 1_000
    end
  end

  defp stats(samples) do
    sorted = Enum.sort(samples)
    %{median_us: Enum.at(sorted, div(length(sorted), 2)), p95_us: Enum.at(sorted, trunc(length(sorted) * 0.95))}
  end
end

LiveLift.Benchmark.run()
