require "wahwah"

# Walks the local music directory and upserts Track rows (source: "local").
# Incremental: unchanged files (by mtime) are skipped. Tracks whose files have
# disappeared are pruned, unless they are currently in the queue.
class LibraryScanner
  # `reason` says WHY nothing was scanned: :disabled (no music_dir configured at
  # all) or :missing (configured but not there right now — an unmounted drive).
  Result = Struct.new(:scanned, :upserted, :pruned, :skipped, :reason, keyword_init: true)

  def initialize(music_dir: PartyConfig.music_dir, extensions: PartyConfig.audio_extensions)
    @music_dir  = music_dir.presence && Pathname.new(music_dir.to_s)
    @extensions = extensions.map(&:downcase).to_set
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

    seen_uids = []
    upserted  = 0

    each_audio_file do |path|
      Rails.logger.debug("[LibraryScanner] checking: #{path}")
      uid = path
      seen_uids << uid
      upserted += 1 if upsert(uid, path)
    end

    pruned = prune_missing(seen_uids)
    Result.new(scanned: seen_uids.size, upserted: upserted, pruned: pruned, skipped: false, reason: nil)
  end

  private

  def each_audio_file
    Dir[File.join(@music_dir, '**', '*')].each do |path|
      next unless File.file?(path)

      ext = File.extname(path).delete_prefix(".").downcase
      yield path if @extensions.include?(ext)
    end
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
