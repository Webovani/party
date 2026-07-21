# Central place for real-time updates. We use Turbo 8 page refreshes (morphing):
# on any discrete state change (queue edit, playback state, cache status), every
# connected browser re-morphs the page. The now-playing progress bar animates
# client-side between events, so we never broadcast per-second position ticks.
module PartyBroadcaster
  STREAM = "party".freeze

  module_function

  def refresh
    Turbo::StreamsChannel.broadcast_refresh_to(STREAM)
  rescue => e
    Rails.logger.error("[PartyBroadcaster] refresh failed: #{e.class}: #{e.message}")
  end
end
