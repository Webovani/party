# Central place for real-time updates.
#
# Broadcast a signal, never markup: "this region is stale, refetch it". The queue
# and player markup is per-viewer — whose rows get a ✕, who may promote, whose
# skip button says "skip now" — so one copy sent to the whole party can never be
# right for everybody. Each client reloads the frame itself
# (PartyController#queue / #now_playing / #volume) with its own cookies.
#
# Not `broadcast_refresh_to`: it re-morphs every client's WHOLE current page, so a
# ±2% volume tap re-renders everyone's open browse listing — the actor included,
# since the daemon has no `Turbo.current_request_id` for Turbo to suppress on.
#
# The progress bar animates client-side between events, so no per-second position
# ticks are broadcast.
module PartyBroadcaster
  STREAM = "party".freeze

  module_function

  # "Up next" changed: added, removed, re-dealt, or a badge (download, loudness)
  # moved on.
  def queue_changed = reload("queue")

  # What is playing, or its transport state: track change, play/pause/stop, seek,
  # a skip vote landing. Deliberately NOT volume.
  def player_changed = reload("now-playing")

  # Only the volume readout, which is its own frame (see _volume_region).
  def volume_changed = reload("player-volume")

  # A new track started (or stopped): both the bar and the queue moved.
  def track_changed
    player_changed
    queue_changed
  end

  def reload(target)
    Turbo::StreamsChannel.broadcast_action_to(STREAM, action: :reload_frame, target: target)
  rescue => e
    Rails.logger.error("[PartyBroadcaster] reload #{target} failed: #{e.class}: #{e.message}")
  end
end
