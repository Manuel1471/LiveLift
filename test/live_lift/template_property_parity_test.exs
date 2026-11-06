defmodule LiveLift.TemplatePropertyParityTest do
  use ExUnit.Case, async: true

  alias LiveLift.Template

  test "1,000 generated template states match server and browser DOM" do
    item =
      StreamData.fixed_map(%{
        id: StreamData.integer(0..100),
        label: StreamData.member_of(["", "<&>", "é", "😀", "a &amp; b"]),
        visible: StreamData.member_of([true, false, nil, 0])
      })

    state =
      StreamData.fixed_map(%{
        label: StreamData.member_of(["", "<&>", "é", "😀", "a &amp; b"]),
        title: StreamData.member_of(["", "<&>", "a &amp; b"]),
        visible: StreamData.member_of([true, false, nil, 0]),
        items: StreamData.uniq_list_of(item, uniq_fun: & &1.id, max_length: 5)
      })

    templates = [
      ~s(<p title="A &amp; B">{@label}</p>),
      ~s(<section :if={@visible} title="{@title}">{@label}</section>),
      ~s(<ul><li :for={item <- @items} :key={item.id}>{@item.label}</li></ul>),
      ~s(<div><p :for={item <- @items} :key={item.id} :if={item.visible}>{@item.label}</p><output>{@label}</output></div>)
    ]

    samples = state |> StreamData.seeded(20_261_106) |> Enum.take(250)

    cases =
      for source <- templates,
          state <- samples do
        tree = Template.compile(source, "property_template.ex")
        html = tree |> Template.render_server(state) |> Phoenix.HTML.safe_to_string()
        %{tree: tree, state: state, html: html}
      end

    file =
      Path.join(
        System.tmp_dir!(),
        "live_lift_template_parity_#{System.unique_integer([:positive])}.json"
      )

    try do
      File.write!(file, Jason.encode!(cases))
      script = Path.expand("../../bench/template_parity.mjs", __DIR__)
      {output, 0} = System.cmd("node", [script, file], stderr_to_stdout: true)
      assert output =~ "1000 template cases matched"
    after
      File.rm(file)
    end
  end
end
