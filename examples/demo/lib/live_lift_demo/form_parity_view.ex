defmodule LiveLiftDemo.FormParityView do
  use LiveLift.Client

  client_template("""
  <section title="Forms &amp; entities">
    <label>Enabled <input type="checkbox" checked={@enabled} $change="toggle" /></label>
    <select aria-label="Choice" $change="choose">
      <option value="a" selected={@first}>A</option>
      <option value="b" selected={@second}>B</option>
    </select>
    <textarea aria-label="Note" $input="edit">{@note}</textarea>
    <output>{@note}</output>
    <button type="button" $click="reset">Reset form</button>
  </section>
  """)

  defclient(toggle(state, event), do: %{state | enabled: event.checked})

  defclient(choose(state, event),
    do: %{state | first: event.value == "a", second: event.value == "b"}
  )

  defclient(edit(state, event), do: %{state | note: event.value})

  defclient(reset(state),
    do: %{state | enabled: true, first: true, second: false, note: "A & <B>"}
  )
end
