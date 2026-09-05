class PartyController < ApplicationController
  def index
    load_app_shell
  end

  # ---- Independently fetched UI regions ----
  #
  # Each answers the `src` of its own turbo-frame, so the markup renders with the
  # requesting guest's cookies — see PartyBroadcaster.
  #
  # No `require_nick`: a stale frame must degrade to a nick-less render, not a
  # redirect the frame would treat as missing content.

  def queue
    render partial: "party/queue_region", locals: { queue: QueueItem.waiting }
  end

  def now_playing
    player = PlayerState.instance
    render partial: "party/now_playing_region",
           locals: { player: player, current_item: player.current_queue_item,
                     votes_to_skip: PartyConfig[:votes_to_skip].to_i }
  end

  def volume
    render partial: "party/volume_region", locals: { player: PlayerState.instance }
  end
end
