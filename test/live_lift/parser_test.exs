defmodule LiveLift.ParserTest do
  use ExUnit.Case, async: true

  alias LiveLift.Template.Parser

  defmodule ChangedParser do
    def parse!(_source, _opts), do: {:ok, []}
  end

  test "a missing LiveView parser fails with an actionable source location" do
    assert_raise ArgumentError, ~r/view.ex:1:.*compatible HEEx parser.*server/, fn ->
      Parser.parse_with!("<p>Hi</p>", "view.ex", MissingLiveViewParser)
    end
  end

  test "a changed LiveView parser result fails with an actionable source location" do
    assert_raise ArgumentError, ~r/view.ex:1:.*unsupported tree.*server/, fn ->
      Parser.parse_with!("<p>Hi</p>", "view.ex", ChangedParser)
    end
  end
end
