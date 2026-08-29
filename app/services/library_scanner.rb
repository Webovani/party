require "wahwah"

# Walks the local music directory and upserts Track rows (source: "local").
# Incremental: unchanged files (by mtime) are skipped. Tracks whose files have
# disappeared are pruned, unless they are currently in the queue.
class LibraryScanner
  # `reason` says WHY nothing was scanned: :disabled (no music_dir configured at
  # all) or :missing (configured but not there right now — an unmounted drive).
  Result = Struct.new(:scanned, :upserted, :pruned, :skipped, :reason, keyword_init: true)

  # How often the progress callback fires while walking. Throttled here because
  # only the scanner knows how fast it ticks, and 22k callbacks is not progress
  # reporting; how (and whether) to render a tick is the caller's business.
  PROGRESS_INTERVAL = 0.2

  # progress: an optional callable invoked as
  #   (phase, scanned:, total:, upserted:, path:)
  # with phase in :listing (finding the audio files — `total` is not known yet,
  # `scanned` is how many have been found so far), :listed (the walk is done and
  # `total` is now known), :scanning (one file done, `path` is the file just
  # handled) and :pruning. :listing and :scanning are throttled; :listed and the
  # last :scanning tick always fire. A scan of a real library
  # takes minutes; without this it is silent from the first file to the summary.
  def initialize(music_dir: PartyConfig.music_dir, extensions: PartyConfig.audio_extensions,
                 progress: nil)
    @music_dir  = music_dir.presence && Pathname.new(music_dir.to_s)
    @extensions = extensions.map(&:downcase).to_set
    @progress   = progress
  end

  def call
    # Both paths return WITHOUT pruning: the index is left exactly as it is, so
    # unplugging the drive — or switching the library off and back on — costs
    # nothing but the time to rescan.
    if @music_dir.nil?
      Rails.logger.info("[LibraryScanner] no music_dir configured; local library is off")
      return Result.new(scanned: 0, upserted: 0, pruned: 0, skipped: true, reason: :disabled)
    end

    unless @music_dir.directory?
      Rails.logger.warn("[LibraryScanner] #{@music_dir} not present (unmounted?); skipping scan")
      return Result.new(scanned: 0, upserted: 0, pruned: 0, skipped: true, reason: :missing)
    end

    # Collect the file list first: knowing the total is what makes the progress
    # a fraction rather than a number climbing towards nothing in particular.
    # The walk is announced (:listing) so the wait for it is not silent either.
    paths = []
    each_audio_file do |path|
      paths << path
      report(:listing, scanned: paths.size)
    end
    upserted = 0
    total    = paths.size
    report(:listed, scanned: total, total: total)

    paths.each_with_index do |path, index|
      Rails.logger.debug("[LibraryScanner] checking: #{path}")
      upserted += 1 if upsert(path, path)
      report(:scanning, scanned: index + 1, total: total, upserted: upserted, path: path,
                        force: index + 1 == total)
    end

    report(:pruning, scanned: total, total: total, upserted: upserted)
    pruned = prune_missing(paths)
    Result.new(scanned: total, upserted: upserted, pruned: pruned, skipped: false, reason: nil)
  end

  private

  # Block form of Dir.glob, so paths arrive as they are found rather than in one
  # batch at the end — that is what lets the listing phase report a running count.
  def each_audio_file
    Dir.glob(File.join(@music_dir, "**", "*")) do |path|
      next unless File.file?(path)

      ext = File.extname(path).delete_prefix(".").downcase
      yield path if @extensions.include?(ext)
    end
  end

  THROTTLED_PHASES = %i[ listing scanning ].freeze

  def report(phase, force: false, scanned:, total: nil, upserted: 0, path: nil)
    return if @progress.nil?

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if !force && THROTTLED_PHASES.include?(phase) &&
       @last_report && now - @last_report < PROGRESS_INTERVAL
      return
    end

    @last_report = now
    @progress.call(phase, scanned: scanned, total: total, upserted: upserted, path: path)
  end

  # Returns true if the row was created or updated, false if skipped (unchanged).
  def upsert(uid, path)
    track = Track.find_or_initialize_by(source: "local", source_uid: uid)
    mtime = File.mtime(path)

    # Compare at whole-second granularity: the DB column truncates the sub-second
    # precision that File#mtime carries, and epoch seconds are timezone-safe.
    if track.persisted? && track.local_path == path &&
       track.file_mtime.present? && track.file_mtime.to_i >= mtime.to_i
      return false
    end

    apply_tags(track, path)
    track.local_path = sanitize(path)
    track.file_mtime = mtime
    track.save!
    true
  end

  def apply_tags(track, path)
    filename = File.basename(path, File.extname(path))
    tag = WahWah.open(path)
    track.title    = sanitize(tag.title.presence) || filename
    track.artist   = sanitize(tag.artist.presence)
    track.album    = sanitize(tag.album.presence)
    track.duration_ms = tag.duration ? (tag.duration.to_f * 1000).round : nil
  rescue => e
    Rails.logger.warn("[LibraryScanner] tag read failed for #{path}: #{e.class}: #{e.message}")
    track.title ||= filename
  end

  def sanitize(string)
    return nil if string.blank?

    string.gsub("\0", "")
  end

  # Remove local tracks whose files vanished, except those still queued/playing.
  def prune_missing(seen_uids)
    scope = Track.local
    scope = scope.where.not(source_uid: seen_uids) if seen_uids.any?
    scope.where.missing(:queue_items).delete_all
  end
end
