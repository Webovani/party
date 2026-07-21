# Eagerly caches EVERY queued YouTube track (in play order, soonest first). Caching
# all of them — not just the next few — means a reshuffle (or a "play next") can't
# surface an un-cached track and cause silence. The queue is length-capped, so this
# stays bounded. Safe to call after any queue change.
class PrecacheQueueJob < ApplicationJob
  queue_as :default

  def perform
    QueueItem.waiting.each do |item|
      track = item.track
      next unless track.youtube?
      next if track.cache_status == "pending"
      next if track.cache_status == "ready" && track.ready_to_play?

      CacheYoutubeTrackJob.perform_later(track.id)
    end
  end
end
