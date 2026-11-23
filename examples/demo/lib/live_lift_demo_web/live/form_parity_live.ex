defmodule LiveLiftDemoWeb.FormParityLive do
  use LiveLiftDemoWeb, :live_view

  def render(assigns) do
    ~H"""
    <main>
      <h1>Form parity fixture</h1>
      <.live_component module={LiveLiftDemo.FormParityView} id="form-parity" />
    </main>
    """
  end
end
