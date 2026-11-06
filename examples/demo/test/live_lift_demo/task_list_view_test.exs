defmodule LiveLiftDemo.TaskListViewTest do
  use ExUnit.Case, async: true

  alias LiveLiftDemo.TaskListView

  test "adds, edits, reorders, and removes app-owned items in Elixir" do
    initial = %{
      items: [%{id: 1, name: "First"}],
      next_id: 2,
      draft: "",
      has_items: true,
      empty: false
    }

    with_draft = TaskListView.set_draft(initial, %{value: "Second"})
    added = TaskListView.add(with_draft)
    assert Enum.map(added.items, & &1.name) == ["First", "Second"]
    assert added.draft == ""

    edited = TaskListView.edit(added, %{value: "Updated", params: %{id: 2}})
    assert Enum.map(TaskListView.reverse(edited).items, & &1.name) == ["Updated", "First"]

    remaining = TaskListView.remove(edited, %{params: %{id: 1}})
    assert Enum.map(remaining.items, & &1.id) == [2]
    assert TaskListView.remove(remaining, %{params: %{id: 2}}).empty
  end
end
