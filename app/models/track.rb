class Track < ApplicationRecord
  SOURCES       = %w[local youtube].freeze
  CACHE_STATUSES = %w[none pending ready error].freeze

  has_many :queue_items, dependent: :restrict_with_error

  validates :source, inclusion: { in: SOURCES }
  validates :source_uid, presence: true, uniqueness: { scope: :source }
  validates :title, presence: true

  scope :local,   -> { where(source: "local") }
  scope :youtube, -> { where(source: "youtube") }
  # Tracks that have been played or skipped at least once.
  scope :history, -> { where(id: QueueItem.where(state: %w[played skipped]).select(:track_id)) }

  # Full-text search over the maintained tsvector, ranked by relevance. Each
  # word is matched as a prefix (lexeme:*), so "beat disc" finds "Beatles –
  # Discovery". Terms are AND-ed. Non-word characters are ignored.
  scope :search, ->(query) {
    terms = query.to_s.scan(/[[:word:]]+/)
    next none if terms.empty?

    tsquery = terms.map { |t| "#{t}:*" }.join(" & ")
    where("search_vector @@ to_tsquery('simple', :q)", q: tsquery)
      .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array([
        "ts_rank(search_vector, to_tsquery('simple', ?)) DESC", tsquery
      ])))
  }

  def local?   = source == "local"
  def youtube? = source == "youtube"

  # Normalized result hash (same shape the sources emit), preserving the track's
  # real source so mixed-source lists (history) re-queue correctly.
  def to_search_result
    {
      source: source, source_uid: source_uid, title: title, artist: artist,
      album: album, duration_ms: duration_ms, thumbnail_url: thumbnail_url,
      local_path: local_path
    }
  end

  def youtube_url
    "https://www.youtube.com/watch?v=#{source_uid}" if youtube?
  end

  # Absolute path mpv should load, or nil if not currently playable.
  def playable_path
    local? ? local_path : cache_path
  end

  # Is the audio available on disk right now?
  def ready_to_play?
    path = playable_path
    return false if path.blank?
    return File.exist?(path) if local?

    cache_status == "ready" && File.exist?(path)
  end

  # Upsert a track from a normalized source result hash.
  # Keeps existing cache/library fields; refreshes metadata.
  def self.upsert_from_result(result)
    track = find_or_initialize_by(source: result[:source], source_uid: result[:source_uid])
    track.title         = result[:title].presence || track.title || result[:source_uid]
    track.artist        = result[:artist]        if result.key?(:artist)
    track.album         = result[:album]         if result.key?(:album)
    track.duration_ms ||= result[:duration_ms]
    track.thumbnail_url = result[:thumbnail_url] if result[:thumbnail_url].present?
    track.local_path    = result[:local_path]    if result.key?(:local_path)
    track.save!
    track
  end
end
