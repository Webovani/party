module ApplicationHelper
  # Inline SVG icons (24x24, currentColor) for player controls.
  PLAYER_ICONS = {
    play:   '<path d="M8 5v14l11-7z"/>',
    pause:  '<path d="M6 5h4v14H6zM14 5h4v14h-4z"/>',
    stop:   '<rect x="6" y="6" width="12" height="12" rx="1.5"/>',
    next:   '<path d="M6 5v14l8.5-7z"/><rect x="15.5" y="5" width="2.5" height="14" rx="1"/>',
    volume: '<path d="M4 9v6h3.5L12 19V5L7.5 9H4z"/><path d="M15.5 8.5a4 4 0 0 1 0 7" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>'
  }.freeze

  # Which of the three top-level tabs the current scope belongs to.
  def active_browse_tab(scope)
    return :home if scope.nil?

    scope[:browse] == "history" ? :history : :library
  end

  # What a search from here would actually cover. Sole source of the input's
  # placeholder — the old "Type to search…" hint said the same thing a second time
  # and was removed, so the library count it carried lives here now.
  def scope_search_target(scope)
    return (local_library? ? "your local library and YouTube" : "YouTube") if scope.nil?

    case scope[:browse]
    when "history" then "played history"
    when "all"     then "all #{number_with_delimiter(library_track_count)} songs in library"
    when "albums"  then scope[:album].present?      ? "in #{scope[:label]}" : "albums and their songs"
    when "artists" then scope[:artist].present?     ? "in #{scope[:label]}" : "artists and their songs"
    when "folders" then scope[:path].to_s.present?  ? "in #{scope[:label]}" : "folders and their songs"
    else "in #{scope[:label]}"
    end
  end

  # LibraryController already has it on a browse render; a search in All mode does
  # not, so fall back to counting rather than letting the placeholder change
  # wording depending on how you arrived.
  def library_track_count = @library_total ||= Track.local.count

  # Rendered server-side AND re-applied by the scope controller: frame navigation
  # doesn't re-render the controls, and the input is permanent, so the server's
  # version only lands on a full page load.
  def search_placeholder(scope) = "Search #{scope_search_target(scope)}…"

  # Browser tab title. Song first: a tab strip truncates the end, and the song is
  # the part worth reading at a glance. Updates on its own because a track change
  # broadcasts a page refresh, which re-renders the whole document.
  #
  # Only set from a full page render — a turbo-frame response's <head> is discarded
  # by Turbo, so the ivars being nil there costs nothing.
  def document_title(player, item)
    track = item&.track
    return "Party" if track.nil? || player.nil? || player.stopped?

    name = track_label(track)
    "#{player.paused? ? "⏸" : "▶"} #{name} · Party"
  end

  # Tab-title label only — nothing else renders through this.
  #
  # YouTube's "artist" is the uploading channel, which is either repeated in the
  # video title ("Knife Party" + "Knife Party - 'Internet Friends'") or is not the
  # artist at all ("AFM Records" for a DYNAZTY track). The video title is the one
  # dependable field, so that is all the title uses. Local tags are trustworthy.
  def track_label(track)
    title = track.title.to_s.strip
    return title if track.youtube?

    artist = track.artist.to_s.strip
    artist.blank? ? title : "#{artist} – #{title}"
  end

  LIBRARY_MODES = %w[all artists albums folders].freeze

  # The library sub-mode a scope belongs to, or nil outside the library.
  def library_mode(scope)
    return nil unless scope && LIBRARY_MODES.include?(scope[:browse])

    scope[:browse].to_sym
  end

  # Heading above the collection rows in a scoped search result.
  def entry_group_label(scope)
    { "artists" => "Artists", "albums" => "Albums", "folders" => "Folders" }
      .fetch(scope&.dig(:browse), "Collections")
  end

  def player_icon(name)
    raw(%(<svg class="icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">#{PLAYER_ICONS.fetch(name.to_sym)}</svg>))
  end

  # 225000 -> "3:45", 3723000 -> "1:02:03", nil -> nil
  def format_ms(ms)
    return nil if ms.blank?

    total = ms.to_i / 1000
    h = total / 3600
    m = (total % 3600) / 60
    s = total % 60
    h.positive? ? format("%d:%02d:%02d", h, m, s) : format("%d:%02d", m, s)
  end

  # Hidden-field params for the "add to queue" button from a search result hash.
  def result_params(result)
    result.slice(:source, :source_uid, :title, :artist, :album,
                 :duration_ms, :thumbnail_url, :local_path)
          .compact
  end

  # Normalize a Track record into the result-card shape (delegates to the model).
  def track_to_result(track)
    track.to_search_result
  end

  # Link target for jumping from a local result to its album browse view.
  # Returns { params:, label: } or nil when there's no artist to browse by.
  def local_album_nav(result)
    return nil unless local_library?
    return nil unless result[:source] == "local" && result[:artist].present?

    params = { browse: "artists", artist: result[:artist] }
    params[:album] = result[:album] if result[:album].present?
    { params: params, label: result[:album].presence || result[:artist] }
  end

  # Link target for jumping from a local result to its containing folder.
  def local_folder_nav(result)
    rel = local_folder_rel(result)
    return nil if rel.nil?

    { params: { browse: "folders", path: rel },
      label: rel.empty? ? "Library root" : File.basename(rel) }
  end

  private

  # Folder of a local file, relative to music_dir ("" for the root); nil if the
  # result isn't a local file under music_dir.
  def local_folder_rel(result)
    return nil unless local_library?
    return nil unless result[:source] == "local" && result[:local_path].present?

    music = (@party_music_dir ||= LocalLibrary.new.music_dir)
    prefix = music.end_with?("/") ? music : "#{music}/"
    path = result[:local_path]
    return nil unless path.start_with?(prefix)

    dir = File.dirname(path.delete_prefix(prefix))
    dir == "." ? "" : dir
  end
end
