defmodule LiveLift.CondParityTest do
  use ExUnit.Case, async: true

  defmodule Actions do
    use LiveLift.Client

    defclient(lazy(state),
      do:
        cond do
          state.flag -> 1
          state.missing -> 2
        end
    )

    defclient(no_match(state),
      do:
        cond do
          state.flag -> 1
        end
    )
  end

  test "cond evaluates only the selected branch" do
    assert Actions.lazy(%{flag: true}) == 1
    assert run_node!("console.log(actions.lazy({flag: true}));") == "1\n"
  end

  test "cond without a matching branch raises on both sides" do
    assert_raise CondClauseError, fn -> Actions.no_match(%{flag: false}) end

    {output, status} = run_node_result("actions.no_match({flag: false});")
    assert status != 0
    assert output =~ "LiveLift cond has no true clause"
  end

  defp run_node!(action) do
    {output, 0} = run_node_result(action)
    output
  end

  defp run_node_result(action) do
    path =
      Path.join(System.tmp_dir!(), "live_lift_cond_#{System.unique_integer([:positive])}.mjs")

    try do
      File.write!(path, LiveLift.Client.Compiler.compile_module(Actions) <> "\n" <> action)
      System.cmd("node", [path], stderr_to_stdout: true)
    after
      File.rm(path)
    end
  end
end
