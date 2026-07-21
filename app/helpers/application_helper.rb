module ApplicationHelper
  # Inline SVG icons (24x24, currentColor) for player controls.
  PLAYER_ICONS = {
    play:   '<path d="M8 5v14l11-7z"/>',
    pause:  '<path d="M6 5h4v14H6zM14 5h4v14h-4z"/>',
    stop:   '<rect x="6" y="6" width="12" height="12" rx="1.5"/>',
    next:   '<path d="M6 5v14l8.5-7z"/><rect x="15.5" y="5" width="2.5" height="14" rx="1"/>',
    volume: '<path d="M4 9v6h3.5L12 19V5L7.5 9H4z"/><path d="M15.5 8.5a4 4 0 0 1 0 7" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>'
  }.freeze

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
    return nil unless result[:source] == "local" && result[:local_path].present?

    music = (@party_music_dir ||= LocalLibrary.new.music_dir)
    prefix = music.end_with?("/") ? music : "#{music}/"
    path = result[:local_path]
    return nil unless path.start_with?(prefix)

    dir = File.dirname(path.delete_prefix(prefix))
    dir == "." ? "" : dir
  end
end
