defmodule ConsumerLiftWeb.BrowserSwitchController do
  use ConsumerLiftWeb, :controller

  def update(conn, %{"mode" => mode}) when mode in ~w(enabled global component) do
    Application.put_env(:live_lift, :enabled, mode != "global")

    Application.put_env(
      :live_lift,
      :disabled_components,
      if(mode == "component", do: [ConsumerLiftWeb.CounterComponent], else: [])
    )

    send_resp(conn, 204, "")
  end
end
