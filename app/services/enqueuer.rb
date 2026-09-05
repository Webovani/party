# Adds a search result to the shared queue, enforcing the fair-use rules, then
# triggers caching and notifies the player daemon.
class Enqueuer
  class Rejected < StandardError; end

  def initialize(nick)
    @nick = nick.to_s
  end

  def enqueue(result)
    raise Rejected, "Pick a nickname first." if @nick.blank?

    result = result.to_h.symbolize_keys
    # The single choke point for "no local library here". Worth refusing rather
    # than letting it through: a local track whose file is missing parks the
    # player on it forever — unlike a dead YouTube link, nothing counts attempts
    # and drops it (see CacheYoutubeTrackJob).
    if result[:source].to_s == "local" && !PartyConfig.local_library?
      raise Rejected, "No local library on this box — YouTube only."
    end

    track = Track.upsert_from_result(result)
    enforce_fair_use!(track)

    # Re-adding a track that previously failed to cache gets a fresh download
    # budget (see CacheYoutubeTrackJob::MAX_ATTEMPTS).
    if track.youtube? && !track.ready_to_play? && (track.cache_status == "error" || track.cache_attempts.positive?)
      track.update!(cache_status: "none", cache_attempts: 0, last_error: nil)
    end

    item = QueueItem.create!(track: track, queued_by: @nick)

    AnalyzeLoudnessJob.perform_later(track.id) unless track.loudness_measured?
    PrecacheQueueJob.perform_later
    PlayerCommands.queue_changed
    PartyBroadcaster.queue_changed # update all clients even if the player is offline
    item
  end

  private

  def enforce_fair_use!(track)
    if QueueItem.active.count >= max_queue_length
      raise Rejected, "The queue is full (max #{max_queue_length})."
    end

    if QueueItem.pending_count_for(@nick) >= max_per_user
      raise Rejected, "You already have #{max_per_user} tracks queued — let others have a turn."
    end

    if QueueItem.track_already_active?(track)
      raise Rejected, "That track is already in the queue."
    end
  end

  def max_queue_length = PartyConfig[:max_queue_length].to_i
  def max_per_user     = PartyConfig[:max_queue_per_user].to_i
end
