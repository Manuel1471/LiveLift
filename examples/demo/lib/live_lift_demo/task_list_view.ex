defmodule LiveLiftDemo.TaskListView do
  use LiveLift.Client

  client_template("""
  <section class="task-panel" aria-label="Custom client list">
    <div class="panel-topline"><span class="eyebrow"><span class="status-dot"></span> YOUR COMPONENTS / CLIENT</span><span class="runtime-pill">Keyed DOM</span></div>
    <div class="panel-heading"><div><h2>Build your own UI</h2><p>This list and its item component are defined by the app in Elixir.</p></div></div>
    <div class="task-add">
      <input type="text" aria-label="New task" placeholder="Write a task..." value="{@draft}" $input="set_draft" />
      <button type="button" $click="add">Add task</button>
    </div>
    <ul class="task-list" :if={@has_items}>
      <li :for={item <- @items} :key={item.id}>
        <LiveLiftDemo.TaskItem item={item} />
      </li>
    </ul>
    <p class="task-empty" :if={@empty}>Your list is empty. Add a task above.</p>
    <button type="button" class="task-reverse" $click="reverse">Reverse order ↔</button>
  </section>
  """)

  defclient(set_draft(state, event),
    do: %{
      items: state.items,
      next_id: state.next_id,
      draft: event.value,
      has_items: state.has_items,
      empty: state.empty
    }
  )

  defclient(add(state),
    do:
      if(state.draft == "",
        do: state,
        else: %{
          items: state.items ++ [%{id: state.next_id, name: state.draft}],
          next_id: state.next_id + 1,
          draft: "",
          has_items: true,
          empty: false
        }
      )
  )

  defclient(remove(state, event),
    do: %{
      items: Enum.reject(state.items, fn item -> item.id == event.params.id end),
      next_id: state.next_id,
      draft: state.draft,
      has_items: Enum.reject(state.items, fn item -> item.id == event.params.id end) != [],
      empty: Enum.reject(state.items, fn item -> item.id == event.params.id end) == []
    }
  )

  defclient(edit(state, event),
    do: %{
      items:
        Enum.map(state.items, fn item ->
          if(item.id == event.params.id,
            do: Map.put(item, :name, event.value),
            else: item
          )
        end),
      next_id: state.next_id,
      draft: state.draft,
      has_items: state.has_items,
      empty: state.empty
    }
  )

  defclient(reverse(state),
    do: %{
      items: Enum.reverse(state.items),
      next_id: state.next_id,
      draft: state.draft,
      has_items: state.has_items,
      empty: state.empty
    }
  )
end
