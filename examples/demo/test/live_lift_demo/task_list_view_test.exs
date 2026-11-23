defmodule LiveLiftDemo.TaskListViewTest do
  use ExUnit.Case, async: true

  alias LiveLiftDemo.TaskListView

  test "adds, edits, reorders, and removes app-owned items in Elixir" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        items: [%{id: "1", form_id: "edit-task-1", name: "First"}],
        next_id: 2,
        draft: "",
        empty: false
      }
    }

    assert {:reply, _, socket} =
             TaskListView.handle_event("set_draft", %{"value" => "Second"}, socket)

    assert {:reply, %{state: %{items: items, draft: ""}}, socket} =
             TaskListView.handle_event("add", %{}, socket)

    assert Enum.map(items, & &1.name) == ["First", "Second"]

    assert {:reply, _, socket} =
             TaskListView.handle_event("edit", %{"row_id" => "2", "value" => "Updated"}, socket)

    assert {:reply, %{state: %{items: items}}, socket} =
             TaskListView.handle_event("reverse", %{}, socket)

    assert Enum.map(items, & &1.name) == ["Updated", "First"]

    assert {:reply, %{state: %{items: [%{id: "2"}]}}, socket} =
             TaskListView.handle_event("remove", %{"id" => "1"}, socket)

    assert {:reply, %{state: %{items: [], empty: true}}, _} =
             TaskListView.handle_event("remove", %{"id" => "2"}, socket)
  end
end
