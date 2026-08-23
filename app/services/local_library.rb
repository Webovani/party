# Hierarchical browsing of the indexed local library (Track rows, source "local").
# Two axes: by tag (Artist -> Album -> tracks) and by filesystem (Folder tree).
# local_path / source_uid are absolute paths under music_dir.
class LocalLibrary
  ENTRY_LIMIT = 50

  # A browse row: an artist, album, or folder the user can drill into or bulk-add.
  # `sub` is a secondary line (an album's artist, a matched folder's parent).
  Entry = Struct.new(:kind, :label, :sub, :count, :nav, :add, keyword_init: true)

  # Raised rather than returning something usable: with a blank music_dir,
  # File.expand_path("") is the working directory, which would quietly make the
  # whole app root "the library". Every caller is behind PartyConfig.local_library?
  # already, so this only fires on a path that forgot to check.
  class Disabled < StandardError; end

  def music_dir
    @music_dir ||= File.expand_path(
      PartyConfig.music_dir || raise(Disabled, "No local library configured (music_dir is blank)")
    )
  end

  # ---- Artist / Album ----

  # Artists with at least one tagged track (untagged tracks are reachable via
  # folders or search), ordered case-insensitively with counts.
  def artists
    Track.local.where.not(artist: [nil, ""])
         .group(:artist).order(Arel.sql("lower(artist)")).count
         .map do |artist, n|
      Entry.new(kind: :artist, label: artist, count: n,
                nav: { browse: "artists", artist: artist }, add: nil)
    end
  end

  def albums(artist)
    counts = Track.local.where(artist: artist).group(:album).count
    merged = Hash.new(0)
    counts.each { |album, n| merged[album.presence] += n } # fold nil and "" together
    merged.sort_by { |album, _| album.to_s.downcase }.map do |album, n|
      Entry.new(kind: :album, label: album || "Unknown album", count: n,
                nav: { browse: "artists", artist: artist, album: album.to_s },
                add: { artist: artist, album: album.to_s })
    end
  end

  # Every album in the library, flattened across artists — the "Albums" browse
  # mode. Grouped by (artist, album) because album titles repeat ("Greatest Hits").
  def all_albums
    album_entries(Track.local.where.not(album: [nil, ""]))
  end

  # ---- Searching a collection (not its tracks) ----

  # Artists / albums / folders matching the query. Songs are searched separately
  # (see SearchController), so a scoped search returns both the collections that
  # match and the tracks inside them.
  def search_entries(scope, query)
    return [] if query.blank?

    case scope[:browse]
    when "artists" then scope[:artist].present? ? [] : search_artists(query)
    when "albums"  then scope[:album].present?  ? [] : search_albums(query)
    when "folders" then search_folders(scope[:path], query)
    else []
    end
  end

  def search_artists(query)
    Track.local.where.not(artist: [nil, ""])
         .where("#{Track.unaccent('artist')} ILIKE #{Track.unaccent('?')}", contains(query))
         .group(:artist).order(Arel.sql("lower(artist)")).count
         .first(ENTRY_LIMIT)
         .map do |artist, n|
      Entry.new(kind: :artist, label: artist, count: n,
                nav: { browse: "artists", artist: artist }, add: nil)
    end
  end

  # Albums match on their own title OR their artist, so "abba" finds every ABBA
  # album even though none of them is called that.
  def search_albums(query)
    album_entries(
      Track.local.where.not(album: [nil, ""])
           .where("#{Track.unaccent('album')} ILIKE #{Track.unaccent(':q')} OR #{Track.unaccent('artist')} ILIKE #{Track.unaccent(':q')}", q: contains(query)),
      limit: ENTRY_LIMIT
    )
  end

  # Folders under `rel` whose own name matches. Grouped by the directory that
  # directly holds each track, then matched on EVERY segment of that path — an
  # artist folder like Pop/ABBA holds no tracks itself (they sit in per-album
  # subfolders), so matching only the deepest directory would never find it.
  # The entry is truncated at the matching segment, and counts roll up into it.
  def search_folders(rel, query)
    rel = normalize_rel(rel)
    prefix = rel.empty? ? "#{music_dir}/" : "#{File.join(music_dir, rel)}/"
    esc = ActiveRecord::Base.sanitize_sql_like(prefix)
    tail = "substr(local_path, #{prefix.length + 1})"
    dir  = "regexp_replace(#{tail}, '/[^/]*$', '')"
    needle = ActiveSupport::Inflector.transliterate(query.to_s).downcase

    matched = Hash.new(0)
    Track.local.where("local_path LIKE ?", "#{esc}%/%")
         .group(Arel.sql(dir)).count
         .each do |path, n|
      segments = path.to_s.split("/")
      at = segments.index { |seg| ActiveSupport::Inflector.transliterate(seg).downcase.include?(needle) }
      matched[segments[0..at].join("/")] += n if at
    end

    matched.sort_by { |path, _| path.downcase }.first(ENTRY_LIMIT).map do |path, n|
      child = rel.empty? ? path : File.join(rel, path)
      parent = File.dirname(path)
      Entry.new(kind: :folder, label: File.basename(path), sub: (parent unless parent == "."),
                count: n, nav: { browse: "folders", path: child }, add: { path: child })
    end
  end

  # Ordered by path, not title: there is no track-number column, and filenames
  # are almost always numbered ("03 - …"), so the on-disk order is the album
  # order. Alphabetical-by-title scrambled every album.
  def album_tracks(artist, album)
    scope = Track.local.where(artist: artist)
    scope = album.present? ? scope.where(album: album) : scope.where(album: [nil, ""])
    scope.order(Arel.sql("lower(local_path)"))
  end

  # ---- Folders ----

  # Immediate subfolders (recursive counts) and the tracks directly in `rel`.
  # Returns [Array<Entry>, ActiveRecord::Relation].
  def folder(rel)
    rel = normalize_rel(rel)
    prefix = rel.empty? ? "#{music_dir}/" : "#{File.join(music_dir, rel)}/"
    esc = ActiveRecord::Base.sanitize_sql_like(prefix)
    # PostgreSQL substr() is character-based, so use character length (not bytes).
    tail = "substr(local_path, #{prefix.length + 1})"

    subfolders = Track.local
                      .where("local_path LIKE ?", "#{esc}%/%")
                      .group(Arel.sql("split_part(#{tail}, '/', 1)"))
                      .order(Arel.sql("lower(split_part(#{tail}, '/', 1))")).count
                      .map do |seg, n|
      child = rel.empty? ? seg : File.join(rel, seg)
      Entry.new(kind: :folder, label: seg, count: n,
                nav: { browse: "folders", path: child }, add: { path: child })
    end

    tracks = Track.local
                  .where("local_path LIKE ? AND local_path NOT LIKE ?", "#{esc}%", "#{esc}%/%")
                  .order(Arel.sql("lower(local_path)"))

    [subfolders, tracks]
  end

  # All tracks anywhere under `rel` (recursive) — for bulk-adding a folder.
  def folder_tracks(rel)
    rel = normalize_rel(rel)
    prefix = rel.empty? ? "#{music_dir}/" : "#{File.join(music_dir, rel)}/"
    esc = ActiveRecord::Base.sanitize_sql_like(prefix)
    Track.local.where("local_path LIKE ?", "#{esc}%").order(Arel.sql("lower(local_path)"))
  end

  # Base relation for a browse scope (see ApplicationController#current_browse_scope),
  # for restricting search. Unordered so search can apply its own relevance order.
  def scope_base(scope)
    if scope[:browse] == "folders"
      scope[:path].to_s.present? ? folder_tracks(scope[:path]).reorder(nil) : Track.local
    else
      rel = Track.local
      rel = rel.where(artist: scope[:artist]) if scope[:artist].present?
      rel = rel.where(album: scope[:album])   if scope[:album].present?
      rel
    end
  end

  def album_entries(relation, limit: nil)
    counts = relation.group(:artist, :album).order(Arel.sql("lower(album)")).count
    entries = counts.map do |(artist, album), n|
      Entry.new(kind: :album, label: album, sub: artist.presence, count: n,
                nav: { browse: "albums", artist: artist.to_s, album: album },
                add: { artist: artist.to_s, album: album })
    end
    limit ? entries.first(limit) : entries
  end

  def contains(query) = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s)}%"

  # Strip leading/trailing slashes and drop any "." / ".." segments (no traversal).
  def normalize_rel(rel)
    rel.to_s.split("/").reject { |s| s.empty? || s == "." || s == ".." }.join("/")
  end
end
