# Measures a track's loudness once, on demand. Enqueued when a track is added to
# the queue; for YouTube tracks the file usually isn't downloaded yet, so
# CacheYoutubeTrackJob re-enqueues this after the download lands.
class AnalyzeLoudnessJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 2 # drop the track from the queue after this many failed measurements

  def perform(track_id)
    track = Track.find_by(id: track_id)
    return if track.nil? || track.loudness_measured?
    return unless track.ready_to_play? # youtube: not cached yet — cache job retriggers

    result = LoudnessAnalyzer.new.measure(track.playable_path)
    return give_up(track) if result.nil?

    track.update!(loudness_lufs: result[:lufs], loudness_lufs_hp: result[:lufs_hp],
                  loudness_attempts: 0)
    PartyBroadcaster.refresh # surface the badge
    # The player parks on an unmeasured head, so tell it the wait is over — it
    # would otherwise sit there until the next queue change or track boundary.
    PlayerCommands.queue_changed
  end

  private

  # A track we cannot measure would park the queue head forever, because the
  # player refuses to start anything unmeasured (playing at gain 0 means playing
  # at FULL volume, which is the one outcome we must not risk). So give it the
  # same treatment as an undownloadable video: after MAX_ATTEMPTS, drop it.
  def give_up(track)
    attempts = track.loudness_attempts.to_i + 1
    track.update(loudness_attempts: attempts)
    return if attempts < MAX_ATTEMPTS

    # active == queued + promoted + playing; a promoted one is exactly what
    # blocks the head.
    removed = QueueItem.active.where(track_id: track.id).destroy_all
    return if removed.blank?

    Rails.logger.warn(
      "[AnalyzeLoudnessJob] dropping '#{track.title}' from queue: unmeasurable after #{attempts} attempts"
    )
    PlayerCommands.queue_changed
    PartyBroadcaster.refresh
  end
end
