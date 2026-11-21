defmodule LiveLift.Component.ProcessTimer do
  @moduledoc false

  alias LiveLift.Component.{Compiler, Helpers}

  def extract(body, params, socket, env) do
    live_view? = Phoenix.LiveView in (Module.get_attribute(env.module, :behaviour) || [])
    kernel_self? = {:function, Kernel} in Macro.Env.lookup_import(env, {:self, 0})

    extract(body, params, socket, env, live_view?, kernel_self?)
  end

  def extract(
        [do: {:__block__, _, [{{:., _, [mod, :send_after]}, meta, args}, result]}],
        params,
        {socket, _, _},
        env,
        live_view?,
        kernel_self?
      ) do
    if Macro.expand(mod, env) == Process do
      line = Keyword.get(meta, :line, env.line)

      unless live_view? do
        error!(
          env.file,
          line,
          "the LiveView owns the mailbox; use send_update_after/3 in a LiveComponent"
        )
      end

      with {name, _, context} when is_atom(name) and is_atom(context) <- params,
           [{:self, _, []}, message, delay] <- args,
           true <- kernel_self?,
           true <- is_atom(message) and message not in [nil, true, false],
           true <- is_integer(delay) and delay in 0..60_000,
           {:noreply, {^socket, _, _}} <- result do
        {%{delay: delay, message: message}, line}
      else
        _ ->
          error!(
            env.file,
            line,
            "use a plain params argument, self(), a literal atom message and a literal delay from 0 to 60000 ms, then return {:noreply, socket}"
          )
      end
    end
  end

  def extract(_body, _params, _socket, _env, _live_view?, _kernel_self?), do: nil

  def compile!(%{message: message} = timer, callbacks, helpers, file, line) do
    case Enum.find(callbacks, fn {pattern, _, _, _, _, _} -> matches_atom?(pattern, message) end) do
      {^message, socket, [], body, callback_file, callback_line} ->
        {name, args, body} =
          Compiler.action_unchecked!(
            "run",
            {:_, [], nil},
            socket,
            body,
            callback_file,
            callback_line
          )

        action = {name, args, Helpers.expand!(body, helpers, callback_file, callback_line)}
        Compiler.validate_action!(action, callback_file, callback_line)
        Map.put(timer, :action, action)

      _ ->
        error!(
          file,
          line,
          "define an unguarded handle_info(#{inspect(message)}, socket) clause before any catch-all"
        )
    end
  end

  defp matches_atom?(pattern, message) when is_atom(pattern), do: pattern == message

  defp matches_atom?(pattern, _message)
       when is_list(pattern) or is_number(pattern) or is_binary(pattern) or
              tuple_size(pattern) == 2,
       do: false

  defp matches_atom?({form, _, _}, _) when form in [:{}, :%{}, :%, :<<>>], do: false
  defp matches_atom?(_pattern, _message), do: true

  defp error!(file, line, reason) do
    raise ArgumentError,
          "#{file}:#{line}: unsupported @client Process.send_after/3: #{reason}; keep scheduling on the server"
  end
end
