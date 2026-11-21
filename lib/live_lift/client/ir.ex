defmodule LiveLift.Client.IR do
  @moduledoc false

  @spec normalize(Macro.t()) :: Macro.t()
  def normalize(ast), do: Macro.postwalk(ast, &normalize_node/1)

  @spec test_type(Macro.t()) :: :boolean | :value
  def test_type(value) when is_boolean(value), do: :boolean
  def test_type({:!, _, [_]}), do: :boolean

  def test_type({operator, _, [_, _]}) when operator in [:==, :!=, :<, :<=, :>, :>=],
    do: :boolean

  def test_type(_), do: :value

  defp normalize_node({:|>, _, [source, {callee, metadata, arguments}]})
       when is_list(arguments),
       do: normalize_node({callee, metadata, [source | arguments]})

  defp normalize_node({:|>, _, _}) do
    raise ArgumentError,
          "unsupported client pipe target: use a supported function call or move this handler to the server"
  end

  defp normalize_node({:if, metadata, [condition, branches]}) when is_list(branches) do
    case Keyword.fetch(branches, :do) do
      {:ok, yes} ->
        {:__live_lift_if__, metadata, [condition, yes, Keyword.get(branches, :else)]}

      :error ->
        raise ArgumentError, "unsupported client if: missing do branch"
    end
  end

  defp normalize_node(node), do: node
end
