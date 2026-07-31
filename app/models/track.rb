class Track < ApplicationRecord
  SOURCES       = %w[local youtube].freeze
  CACHE_STATUSES = %w[none pending ready error].freeze

  has_many :queue_items, dependent: :restrict_with_error

  validates :source, inclusion: { in: SOURCES }
  validates :source_uid, presence: true, uniqueness: { scope: :source }
  validates :title, presence: true

  # Diacritic stripping, applied to BOTH the stored index and the query. Must stay
  # byte-identical to the UnaccentViaTranslate migration: the index holds the
  # translated text, so a different mapping here silently stops matching.
  UNACCENT_FROM = "ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝàáâãäåçèéêëìíîïðñòóôõöøùúûüýÿĀāĂăĄąĆćĈĉĊċČčĎďĐđĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħĨĩĪīĬĭĮįİıĴĵĶķĸĹĺĻļĽľĿŀŁłŃńŅņŇňŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŦŧŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽž".freeze
  UNACCENT_TO   = "AAAAAACEEEEIIIIDNOOOOOOUUUUYaaaaaaceeeeiiiidnoooooouuuuyyAaAaAaCcCcCcCcDdDdEeEeEeEeEeGgGgGgGgHhHhIiIiIiIiIiJjKkkLlLlLlLlLlNnNnNnOoOoOoRrRrRrSsSsSsSsTtTtTtUuUuUuUuUuUuWwYyYZzZzZz".freeze

  # Wraps a SQL expression in the same translate() the generated columns use.
  def self.unaccent(expr)
    "translate(#{expr}, #{connection.quote(UNACCENT_FROM)}, #{connection.quote(UNACCENT_TO)})"
  end
  scope :local,   -> { where(source: "local") }
  scope :youtube, -> { where(source: "youtube") }
  # Tracks that have been played or skipped at least once.
  scope :history, -> { where(id: QueueItem.where(state: %w[played skipped]).select(:track_id)) }

  # Full-text search over the maintained tsvector, ranked by relevance. Each
  # word is matched as a prefix (lexeme:*), so "beat disc" finds "Beatles –
  # Discovery". Terms are AND-ed. Non-word characters are ignored.
  #
  # Both sides go through the same translate() (see .unaccent), so "cechomor" is an
  # exact hit on "Čechomor". The index stores the stripped form, so unaccenting only
  # the column — or only the query — would never match.
  scope :search, ->(query) {
    terms = query.to_s.scan(/[[:word:]]+/)
    next none if terms.empty?

    tsquery = terms.map { |t| "#{t}:*" }.join(" & ")
    where("search_vector @@ to_tsquery('simple', #{unaccent(":q")})", q: tsquery)
      .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array([
        "ts_rank(search_vector, to_tsquery('simple', #{unaccent('?')})) DESC", tsquery
      ])))
  }

  # pg_trgm word_similarity cutoff, measured against this library: the 0.6 default
  # recovers no typos at all, 0.3 matches almost anything ("empriestate" pulled 25
  # unrelated rows). 0.4 recovers real mistyping and still rejects noise.
  FUZZY_THRESHOLD = 0.4

  # Trigram fallback for typos prefix-matching cannot recover from ("nohavcia").
  # Each term must approximately appear somewhere in title/artist/album, mirroring
  # the AND semantics of `search`.
  scope :fuzzy, ->(query) {
    terms = query.to_s.scan(/[[:word:]]+/)
    next none if terms.empty?

    # Index-assisted `<%` honours this GUC rather than taking a literal, so it has
    # to be set on the connection. Harmless elsewhere: nothing else uses `<%`.
    connection.execute("SET pg_trgm.word_similarity_threshold = #{FUZZY_THRESHOLD}")

    terms.reduce(all) { |rel, term| rel.where("#{unaccent('?')} <% search_text", term) }
         .order(Arel.sql(Track.sanitize_sql_array(
           ["word_similarity(#{unaccent('?')}, search_text) DESC", query]
         )))
  }

  # Exact/prefix first — precise and fast. Trigrams only when that finds nothing,
  # so a typo still returns something without loosening good queries.
  scope :matching, ->(query) {
    exact = search(query)
    next exact if exact.exists?

    fuzzy(query)
  }

  def local?   = source == "local"
  def youtube? = source == "youtube"

  # Defaults mirror config/party.yml. Used via PartyConfig.fetch (not []) so that
  # a config file newer than the running process degrades to these instead of
  # raising KeyError on every render.
  LOUDNESS_TARGET_LUFS = -20.0
  LOUDNESS_MAX_GAIN_DB = 0.0
  LOUDNESS_MIN_GAIN_DB = -20.0
  LOUDNESS_BASS_CORRECTION = 0.5

  # How many dB of this track's measured loudness sit below the analyzer's
  # highpass. Measured across the library this ranges from ~0.7 dB (jangly guitar
  # pop) to ~5.3 dB (psytrance) — which is why two tracks at the same LUFS can
  # sound several dB apart. Never negative: rolling off bass cannot make a file
  # meter louder, so a tiny inversion is gating noise, not signal.
  def bass_share_db
    return 0.0 if loudness_lufs.nil? || loudness_lufs_hp.nil?

    [loudness_lufs - loudness_lufs_hp, 0.0].max
  end

  # The R128 reading pulled part-way toward a midrange-referenced one. At
  # correction 0 this is plain R128; at 1.0 loudness is judged on the highpassed
  # signal alone. The default 0.5 splits the difference — full correction tends to
  # over-boost bass-heavy tracks on a rig that actually reproduces sub.
  def effective_loudness_lufs
    return nil if loudness_lufs.nil?

    correction = PartyConfig.fetch(:loudness_bass_correction, LOUDNESS_BASS_CORRECTION).to_f
    loudness_lufs - (bass_share_db * correction)
  end

  # Both passes present. Rows measured before the highpass pass existed answer
  # false, so the PrecacheQueueJob sweep re-measures them.
  def loudness_measured? = loudness_lufs.present? && loudness_lufs_hp.present?

  # dB to apply so this track plays at the configured target loudness. Clamped —
  # by default max_gain is 0, i.e. we only ever attenuate, so there is no clipping
  # risk and the amp provides the make-up gain. Nil (unmeasured) => no change.
  def loudness_gain_db
    measured = effective_loudness_lufs
    return 0.0 if measured.nil?

    target = PartyConfig.fetch(:loudness_target_lufs, LOUDNESS_TARGET_LUFS).to_f
    (target - measured).clamp(
      PartyConfig.fetch(:loudness_min_gain_db, LOUDNESS_MIN_GAIN_DB).to_f,
      PartyConfig.fetch(:loudness_max_gain_db, LOUDNESS_MAX_GAIN_DB).to_f
    )
  end

  # Deliberately no linear-amplitude helper here. The gain is consumed as dB by
  # mpv's volume filter; mpv's own "volume" property is a cubic scale, and folding
  # an amplitude factor into it once applied every correction three times over.

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

  # Safe to start playing: the file is there AND we know how loud it is. Playing
  # unmeasured means playing at gain 0 — i.e. FULL volume, the loudest possible
  # outcome, at the exact moment we know least. The daemon parks on an unplayable
  # head instead (same treatment as a track that is still downloading).
  def playable? = ready_to_play? && loudness_measured?

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
