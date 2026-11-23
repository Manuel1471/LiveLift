[baseline_path] = System.argv()

baseline_path
|> File.read!()
|> String.replace("defmodule LiveLift.State do", "defmodule LiveLift.BaselineState do",
  global: false
)
|> Code.compile_string(baseline_path)

summarize = fn samples ->
  sorted = Enum.sort(samples)
  percentile = fn fraction -> Enum.at(sorted, ceil(fraction * length(sorted)) - 1) end

  %{
    min: hd(sorted),
    median: percentile.(0.5),
    p95: percentile.(0.95),
    max: List.last(sorted),
    iqr: percentile.(0.75) - percentile.(0.25)
  }
end

for rows <- [100, 1_000] do
  state = %{items: for(index <- 1..rows, do: %{id: "row-#{index}", label: "Row #{index}"})}
  variants = [baseline: LiveLift.BaselineState, candidate: LiveLift.State]

  measure = fn module ->
    start = System.monotonic_time()
    ^state = module.validate!(state)
    System.convert_time_unit(System.monotonic_time() - start, :native, :nanosecond) / 1_000
  end

  for _warmup <- 1..30, {_variant, module} <- variants, do: measure.(module)

  samples =
    Enum.reduce(1..300, %{baseline: [], candidate: []}, fn index, samples ->
      order = if rem(index, 2) == 0, do: variants, else: Enum.reverse(variants)

      Enum.reduce(order, samples, fn {variant, module}, acc ->
        result = measure.(module)
        Map.update!(acc, variant, &[result | &1])
      end)
    end)

  IO.inspect(
    %{
      rows: rows,
      samples: 300,
      validation_us: Map.new(samples, fn {variant, values} -> {variant, summarize.(values)} end)
    },
    pretty: true
  )
end
