# Adds a search result to the shared queue, enforcing the fair-use rules, then
# triggers caching and notifies the player daemon.
class Enqueuer
  class Rejected < StandardError; end

  # Outcome of a bulk add (whole album / folder).
  BulkResult = Struct.new(:added, :skipped, keyword_init: true)

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
    PartyBroadcaster.refresh # update all clients even if the player is offline
    item
  end

  # Add as many of `scope` (a Track relation, e.g. an album or folder) as the
  # fair-use limits allow, skipping duplicates. Notifies once at the end.
  def enqueue_all(scope)
    raise Rejected, "Pick a nickname first." if @nick.blank?

    total = scope.count
    remaining = [max_queue_length - QueueItem.active.count,
                 max_per_user - QueueItem.pending_count_for(@nick)].min
    added = 0

    if remaining.positive?
      # One transaction for the whole batch, so the queue is re-dealt once before
      # commit rather than once per track (see QueueItem#reorder_if_requested).
      QueueItem.transaction do
        scope.limit([remaining * 3, 200].max).each do |track|
          break if added >= remaining
          next if QueueItem.track_already_active?(track)

          QueueItem.create!(track: track, queued_by: @nick)
          AnalyzeLoudnessJob.perform_later(track.id) unless track.loudness_measured?
          added += 1
        end
      end
    end

    if added.positive?
      PrecacheQueueJob.perform_later
      PlayerCommands.queue_changed
      PartyBroadcaster.refresh
    end

    BulkResult.new(added: added, skipped: total - added)
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
