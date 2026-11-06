defmodule LiveLiftDemo.TaskItem do
  use LiveLift.Client.Component

  client_template("""
  <div class="task-item">
    <span class="task-bullet" aria-hidden="true">•</span>
    <input type="text" aria-label="Task name" value="{@item.name}" $input="edit" :params={%{id: @item.id}} />
    <button type="button" class="task-remove" $click="remove" :params={%{id: @item.id}} aria-label="Remove task">×</button>
  </div>
  """)
end
