# Runs after any queue change. Two jobs, both walking the waiting queue:
#
#   * Eagerly caches EVERY queued YouTube track (in play order, soonest first).
#     Caching all of them — not just the next few — means a reshuffle (or a "play
#     next") can't surface an un-cached track and cause silence.
#   * Makes sure every playable queued track has a loudness measurement.
#
# Doing the loudness sweep here (rather than only on enqueue) makes it
# self-healing: tracks queued before the feature existed, or whose measurement
# failed, get picked up on the next queue change. The queue is length-capped, so
# this stays bounded.
class PrecacheQueueJob < ApplicationJob
  queue_as :default

  def perform
    QueueItem.waiting.includes(:track).each do |item|
      track = item.track
      cache_youtube(track)
      AnalyzeLoudnessJob.perform_later(track.id) if !track.loudness_measured? && track.ready_to_play?
    end
  end

  private

  def cache_youtube(track)
    return unless track.youtube?
    return if track.cache_status == "pending"
    return if track.cache_status == "ready" && track.ready_to_play?

    CacheYoutubeTrackJob.perform_later(track.id)
  end
end
