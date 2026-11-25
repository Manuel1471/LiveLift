defmodule LiveLift.Diagnostic do
  @moduledoc false

  @guidance %{
    "E052" =>
      "Use a supported schemaless changeset projection or remove the @client marker to keep it on the server.",
    "E055" =>
      "Use one literal handle_event/3 clause per event with @client true or @client :local and a supported socket update, or keep the handler on the server.",
    "E056" =>
      "Use an expression from the supported client language or remove the @client marker to move it to a server handler.",
    "E057" =>
      "Use literal, safe string keys for event parameters or remove the @client marker to keep the handler on the server.",
    "E058" =>
      "Use a bounded, unguarded private helper or remove the @client marker from the calling handler.",
    "E059" => "Remove the @client marker to keep scheduling on the server.",
    "E060" =>
      "Use supported HEEx in a literal ~H template or Phoenix's colocated .html.heex file, or keep this rendering outside the LiveLift island.",
    "E061" =>
      "Use a supported binding or static attribute, or render this markup in LiveView outside the LiveLift island.",
    "E062" =>
      "Use a local function with literal ~H and explicit props, or render the component in LiveView outside the LiveLift island.",
    "E063" =>
      "Use a supported native binding or try an unmarked event. Keep unsupported binding markup outside the LiveLift island.",
    "E064" => "Use safe HTML and attribute values. Keep event logic in native phx-* bindings.",
    "E065" => "Fix the HEEx syntax at the reported location and compile again."
  }

  def message(code, file, line, reason) do
    "#{file}:#{line}: #{reason} (#{code})\n  #{Map.fetch!(@guidance, code)} See docs/errors/#{code}.md"
  end

  def error!(code, file, line, reason) do
    raise ArgumentError, message(code, file, line, reason)
  end
end
