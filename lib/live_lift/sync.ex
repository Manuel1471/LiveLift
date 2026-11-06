defmodule LiveLift.Sync do
  @moduledoc """
  Sends a versioned patch to a LiveLift island from a LiveView event handler.

  Only fields declared in the island's `server_fields` may appear in `patch`.
  The caller must increment `revision` for each patch sent to that island.
  Older or duplicate revisions are ignored by the browser.
  """

  @spec push(Phoenix.LiveView.Socket.t(), String.t(), non_neg_integer(), map()) ::
          Phoenix.LiveView.Socket.t()
  def push(socket, id, revision, patch)
      when is_binary(id) and is_integer(revision) and revision > 0 and is_map(patch) do
    LiveLift.State.validate!(patch)

    Phoenix.LiveView.push_event(socket, "live_lift:patch", %{
      id: id,
      revision: revision,
      patch: patch
    })
  end

  def push(_socket, _id, _revision, _patch) do
    raise ArgumentError, "LiveLift sync requires an island id, positive revision and map patch"
  end
end
