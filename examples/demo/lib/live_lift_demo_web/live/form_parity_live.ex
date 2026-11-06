defmodule LiveLiftDemoWeb.FormParityLive do
  use LiveLiftDemoWeb, :live_view

  def render(assigns) do
    ~H"""
    <main>
      <h1>Form parity fixture</h1>
      <LiveLift.View.island
        id="form-parity"
        module={LiveLiftDemo.FormParityView}
        state={%{enabled: true, first: true, second: false, note: "A & <B>"}}
      />
    </main>
    """
  end
end
