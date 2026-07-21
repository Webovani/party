class CacheYoutubeTrackJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 2 # drop the track from the queue after this many failed downloads

  def perform(track_id)
    track = Track.find_by(id: track_id)
    return unless track&.youtube?
    return if track.cache_status == "ready" && track.ready_to_play?

    downloader = YoutubeDownloader.new

    # Already on disk from a previous run? Just mark ready.
    if (existing = downloader.cached_file(track.source_uid))
      mark_ready(track, existing.to_s)
      return
    end

    track.update!(cache_status: "pending", last_error: nil)
    PartyBroadcaster.refresh

    path = downloader.download(track.source_uid)
    mark_ready(track, path)
  rescue => e
    Rails.logger.error("[CacheYoutubeTrackJob] track=#{track_id}: #{e.class}: #{e.message}")
    handle_failure(track, e)
  end

  private

  def mark_ready(track, path)
    track.update!(cache_path: path, cache_status: "ready", last_error: nil, cache_attempts: 0)
    PartyBroadcaster.refresh
  end

  # Record the failure; once a track has failed MAX_ATTEMPTS times, give up on it
  # and remove it from the queue so a broken video can't stall playback.
  def handle_failure(track, error)
    return unless track

    attempts = track.cache_attempts.to_i + 1
    track.update(cache_status: "error", last_error: error.message.to_s.first(500), cache_attempts: attempts)

    if attempts >= MAX_ATTEMPTS
      removed = QueueItem.where(track_id: track.id, state: %w[queued playing]).destroy_all
      if removed.present?
        Rails.logger.warn(
          "[CacheYoutubeTrackJob] dropping #{track.source_uid} from queue after #{attempts} failed downloads"
        )
        PlayerCommands.queue_changed # let the player advance past it
      end
    end

    PartyBroadcaster.refresh
  end
end
