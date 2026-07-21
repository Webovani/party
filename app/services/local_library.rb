# Hierarchical browsing of the indexed local library (Track rows, source "local").
# Two axes: by tag (Artist -> Album -> tracks) and by filesystem (Folder tree).
# local_path / source_uid are absolute paths under music_dir.
class LocalLibrary
  # A browse row: an artist, album, or folder the user can drill into or bulk-add.
  Entry = Struct.new(:kind, :label, :count, :nav, :add, keyword_init: true)

  def music_dir
    @music_dir ||= File.expand_path(PartyConfig[:music_dir].to_s)
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

  def album_tracks(artist, album)
    scope = Track.local.where(artist: artist)
    scope = album.present? ? scope.where(album: album) : scope.where(album: [nil, ""])
    scope.order(Arel.sql("lower(coalesce(title, '')), local_path"))
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

  # Strip leading/trailing slashes and drop any "." / ".." segments (no traversal).
  def normalize_rel(rel)
    rel.to_s.split("/").reject { |s| s.empty? || s == "." || s == ".." }.join("/")
  end
end
