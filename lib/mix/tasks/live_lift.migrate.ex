defmodule Mix.Tasks.LiveLift.Migrate do
  @moduledoc """
  Converts a simple legacy client view into a native LiveComponent.

      mix live_lift.migrate lib/my_app/counter_view.ex \
        --module MyAppWeb.Counter --output lib/my_app_web/components/counter.ex

  The command accepts literal `client_template` markup with `$click` buttons,
  text `$input` controls, select `$change` controls, flat `$submit` forms, and
  `defclient` map updates. It rejects
  other forms with a source location rather than generating a component with
  changed behavior. Mount the generated component in place of the old island
  after reviewing its assigns and server event handling.
  """

  use Mix.Task

  alias LiveLift.Template.Parser

  @shortdoc "Converts a supported legacy client view to a LiveComponent"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [module: :string, output: :string])

    if invalid != [] or length(rest) != 1 or !opts[:module] or !opts[:output] do
      Mix.raise(
        "usage: mix live_lift.migrate SOURCE --module MyAppWeb.Counter --output DESTINATION"
      )
    end

    [source_file] = rest
    output_file = opts[:output]

    unless File.regular?(source_file), do: Mix.raise("source file not found: #{source_file}")
    if File.exists?(output_file), do: Mix.raise("destination already exists: #{output_file}")

    source = File.read!(source_file)
    ast = Code.string_to_quoted!(source, file: source_file)
    {legacy, body} = module_body!(ast, source_file)
    expressions = block(body)
    Enum.each(expressions, &validate_declaration!(&1, source_file))

    unless Enum.any?(
             expressions,
             &match?({:use, _, [{:__aliases__, _, [:LiveLift, :Client]}]}, &1)
           ) do
      Mix.raise("#{source_file}:1: #{legacy} must use LiveLift.Client")
    end

    {template, template_line} = template!(expressions, source_file)
    actions = Enum.flat_map(expressions, &action(&1, source_file))

    if actions == [], do: Mix.raise("#{source_file}:1: no one-argument defclient actions found")

    names = Enum.map(actions, &elem(&1, 0))

    if length(names) != length(Enum.uniq(names)),
      do: Mix.raise("#{source_file}:1: duplicate defclient action names")

    heex =
      template
      |> Parser.parse!(source_file)
      |> Enum.map_join(&render_node(&1, source_file, actions))

    LiveLift.Template.compile_liveview(heex, source_file, names)

    module = opts[:module]

    unless Regex.match?(~r/^[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*$/, module) do
      Mix.raise("--module must be a valid Elixir alias")
    end

    handlers = Enum.map_join(actions, "\n\n", &handler/1)

    generated = """
    defmodule #{module} do
      use Phoenix.LiveComponent
      use LiveLift

      def render(assigns) do
        ~H\"\"\"
    #{indent(heex, 4)}
        \"\"\"
      end

    #{indent(handlers, 2)}
    end
    """

    formatted = generated |> Code.format_string!() |> IO.iodata_to_binary()
    File.mkdir_p!(Path.dirname(output_file))
    File.write!(output_file, formatted <> "\n")

    Mix.shell().info("Created #{output_file} from #{source_file}:#{template_line}")

    Mix.shell().info(
      "Replace the old island mount with <.live_component module={#{module}} id=... ... /> after reviewing assigns."
    )
  end

  defp module_body!({:defmodule, _, [name, [do: body]]}, _file),
    do: {Macro.to_string(name), body}

  defp module_body!(_ast, file),
    do: Mix.raise("#{file}:1: expected one top-level legacy defmodule")

  defp block({:__block__, _, expressions}), do: expressions
  defp block(expression), do: [expression]

  defp validate_declaration!({:use, _, [{:__aliases__, _, [:LiveLift, :Client]}]}, _file),
    do: :ok

  defp validate_declaration!({:client_template, _, _}, _file), do: :ok
  defp validate_declaration!({:defclient, _, _}, _file), do: :ok

  defp validate_declaration!({name, meta, _}, file),
    do: Mix.raise("#{file}:#{meta[:line]}: #{name} needs manual migration")

  defp validate_declaration!(_expression, file),
    do: Mix.raise("#{file}:1: unsupported module declaration needs manual migration")

  defp template!(expressions, file) do
    case Enum.filter(expressions, &match?({:client_template, _, _}, &1)) do
      [{:client_template, meta, [template]}] when is_binary(template) ->
        if String.contains?(template, "\"\"\"") do
          Mix.raise(
            "#{file}:#{meta[:line]}: template contains triple quotes; migrate this view manually"
          )
        end

        {template, meta[:line]}

      _ ->
        Mix.raise("#{file}:1: expected one literal client_template; migrate this view manually")
    end
  end

  defp action({:defclient, meta, [{name, _, [{state, _, _}]}, [do: body]]}, file)
       when is_atom(name) and is_atom(state) do
    map_action(name, state, nil, body, file, meta[:line])
  end

  defp action({:defclient, meta, [{name, _, [{state, _, _}, {event, _, _}]}, [do: body]]}, file)
       when is_atom(name) and is_atom(state) and is_atom(event) do
    map_action(name, state, event, body, file, meta[:line])
  end

  defp action({:defclient, meta, _}, file),
    do:
      Mix.raise(
        "#{file}:#{meta[:line]}: defclient requires one state argument and optional event argument for automatic migration"
      )

  defp action(_other, _file), do: []

  defp event_modes(_expression, nil), do: []

  defp event_modes(expression, event) do
    {_expression, modes} =
      Macro.prewalk(expression, [], fn
        {{:., _, [{^event, _, _}, :value]}, _, []} = node, modes ->
          {node, [:value | modes]}

        {{:., _, [{{:., _, [{^event, _, _}, :params]}, _, []}, key]}, _, []} = node, modes
        when is_atom(key) ->
          {node, [:fields | modes]}

        node, modes ->
          {node, modes}
      end)

    modes
  end

  defp map_action(name, state, event, body, file, line) do
    case body do
      {:%{}, _, [{:|, _, [{^state, _, _}, updates]}]} when is_list(updates) ->
        unless updates != [] and Enum.all?(updates, fn {field, _} -> is_atom(field) end) do
          Mix.raise("#{file}:#{line}: #{name} requires literal atom fields")
        end

        fields = Enum.map(updates, &elem(&1, 0))

        if length(fields) != length(Enum.uniq(fields)),
          do: Mix.raise("#{file}:#{line}: #{name} updates the same field twice")

        modes =
          updates
          |> Enum.flat_map(fn {_, expression} -> event_modes(expression, event) end)
          |> Enum.uniq()

        if length(modes) > 1,
          do:
            Mix.raise(
              "#{file}:#{line}: #{name} mixes event.value and event.params; migrate this action manually"
            )

        mode = List.first(modes) || :none
        socket = {:socket, [], nil}

        assignment =
          Enum.reduce(updates, socket, fn {field, expression}, source ->
            rewritten =
              Macro.prewalk(expression, fn
                {{:., dot_meta, [{^state, _, _}, key]}, call_meta, []} ->
                  {{:., dot_meta, [{{:., [], [socket, :assigns]}, [no_parens: true], []}, key]},
                   call_meta, []}

                {{:., _, [{^event, _, _}, :value]}, _, []} when not is_nil(event) ->
                  Code.string_to_quoted!(~s(params["value"]))

                {{:., _, [{{:., _, [{^event, _, _}, :params]}, _, []}, key]}, _, []}
                when not is_nil(event) and is_atom(key) ->
                  Code.string_to_quoted!(~s(params[#{inspect(Atom.to_string(key))}]))

                node ->
                  node
              end)

            {:assign, [], [source, field, rewritten]}
          end)

        if event != nil and variable_used?(assignment, event) do
          Mix.raise(
            "#{file}:#{line}: #{name} uses unsupported event data; migrate this action manually"
          )
        end

        params = if mode == :none, do: {:_params, [], nil}, else: {:params, [], nil}

        LiveLift.Component.Compiler.action!(
          Atom.to_string(name),
          params,
          socket,
          [do: {:{}, [], [:noreply, assignment]}],
          file,
          line
        )

        [{Atom.to_string(name), assignment, mode}]

      _ ->
        Mix.raise(
          "#{file}:#{line}: #{name} must return a map update of state; migrate this action manually"
        )
    end
  end

  defp render_node({:text, value, _}, _file, _actions), do: value
  defp render_node({:body_expr, source, _}, _file, _actions), do: "{#{source}}"

  defp render_node({:block, :tag, tag, attrs, children, _meta, _close}, file, actions) do
    open = render_open(tag, attrs, file, actions)
    open <> Enum.map_join(children, &render_node(&1, file, actions)) <> "</#{tag}>"
  end

  defp render_node({:self_close, :tag, tag, attrs, _meta}, file, actions),
    do: render_open(tag, attrs, file, actions, true)

  defp render_node(node, file, _names),
    do:
      Mix.raise("#{file}:1: unsupported legacy template node #{inspect(node)}; migrate manually")

  defp render_open(tag, attrs, file, actions, self_close \\ false) do
    if Enum.any?(attrs, fn {name, _, _} -> name == "$click" end) and tag != "button" do
      Mix.raise("#{file}:1: $click migration requires a button")
    end

    if Enum.any?(attrs, fn {name, _, _} -> name == "$submit" end) and tag != "form" do
      Mix.raise("#{file}:1: $submit migration requires a form")
    end

    input? = Enum.any?(attrs, fn {name, _, _} -> name == "$input" end)
    change? = Enum.any?(attrs, fn {name, _, _} -> name == "$change" end)

    if input? or change? do
      type =
        Enum.find_value(attrs, fn
          {"type", {:string, value, _}, _} -> value
          _ -> nil
        end)

      unless (input? and ((tag == "input" and type in [nil, "text"]) or tag == "textarea")) or
               (change? and tag == "select") do
        Mix.raise("#{file}:1: $input/$change migration requires a text input, textarea or select")
      end

      case Enum.find(attrs, fn {name, _, _} -> name == "name" end) do
        nil ->
          :ok

        {"name", {:string, "value", _}, _} ->
          :ok

        {"name", _, meta} ->
          Mix.raise("#{file}:#{meta.line}: $input/$change requires name=\"value\" for migration")
      end
    end

    rendered = Enum.map_join(attrs, &render_attr(&1, file, actions))

    target =
      if Enum.any?(attrs, fn {name, _, _} ->
           name in ["$click", "$input", "$change", "$submit"]
         end),
         do: " phx-target={@myself}",
         else: ""

    input_name =
      if (input? or change?) and not Enum.any?(attrs, fn {name, _, _} -> name == "name" end),
        do: " name=\"value\"",
        else: ""

    "<#{tag}#{rendered}#{input_name}#{target}" <> if(self_close, do: " />", else: ">")
  end

  defp render_attr({"$click", {:string, event, _}, meta}, file, actions) do
    unless Enum.any?(actions, fn {name, _, mode} -> name == event and mode == :none end),
      do: Mix.raise("#{file}:#{meta.line}: $click requires a one-argument action #{event}")

    " phx-click=\"#{event}\""
  end

  defp render_attr({"$input", {:string, event, _}, meta}, file, actions) do
    unless Enum.any?(actions, fn {name, _, mode} -> name == event and mode in [:value, :none] end),
           do: Mix.raise("#{file}:#{meta.line}: $input requires a two-argument action #{event}")

    " phx-change=\"#{event}\""
  end

  defp render_attr({"$change", {:string, event, _}, meta}, file, actions) do
    unless Enum.any?(actions, fn {name, _, mode} -> name == event and mode in [:value, :none] end),
           do: Mix.raise("#{file}:#{meta.line}: $change requires a two-argument action #{event}")

    " phx-change=\"#{event}\""
  end

  defp render_attr({"$submit", {:string, event, _}, meta}, file, actions) do
    unless Enum.any?(actions, fn {name, _, mode} -> name == event and mode in [:fields, :none] end),
           do:
             Mix.raise(
               "#{file}:#{meta.line}: $submit requires an action reading event.params fields"
             )

    " phx-submit=\"#{event}\""
  end

  defp render_attr({name, {:expr, source, _}, _meta}, _file, _actions)
       when name in ["checked", "selected"],
       do: " #{name}={#{source}}"

  defp render_attr({name, {:string, value, _}, meta}, file, _names) do
    if String.starts_with?(name, ["$", ":"]) do
      Mix.raise("#{file}:#{meta.line}: #{name} needs manual migration")
    end

    if String.contains?(value, ["&", "\"", "<", ">"]),
      do:
        Mix.raise(
          "#{file}:#{meta.line}: #{name} contains an encoded or unsafe value; migrate manually"
        )

    case Regex.run(~r/^\{@([a-zA-Z_][a-zA-Z0-9_]*)\}$/, value) do
      [_, field] -> " #{name}={@#{field}}"
      nil -> " #{name}=\"#{value}\""
    end
  end

  defp render_attr({name, _value, meta}, file, _names),
    do: Mix.raise("#{file}:#{meta.line}: #{name} needs manual migration")

  defp handler({name, assignment, mode}) do
    params = if mode == :none, do: "_params", else: "params"

    """
    @client true
    def handle_event(#{inspect(name)}, #{params}, socket) do
      {:noreply, #{Macro.to_string(assignment)}}
    end
    """
    |> String.trim_trailing()
  end

  defp variable_used?(ast, name) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^name, _, context} = node, _found when is_atom(context) or is_nil(context) ->
          {node, true}

        node, found ->
          {node, found}
      end)

    found
  end

  defp indent(string, count) do
    prefix = String.duplicate(" ", count)
    string |> String.split("\n") |> Enum.map_join("\n", &(prefix <> &1))
  end
end
