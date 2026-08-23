class LibraryController < ApplicationController
  before_action :require_nick
  before_action :require_local_library

  MODES = %w[all artists albums folders].freeze

  def index
    @library_total = Track.local.count
    # "all" is the landing mode: searching is what people actually do, and the
    # artist list is 3.5k rows they have to page through to reach anything.
    @mode = (MODES.include?(params[:browse]) ? params[:browse] : "all").to_sym
    # Normalise so a bare /library still resolves to a scope (and so the Library
    # tab lights up) rather than reading as "no scope".
    params[:browse] = @mode.to_s
    send(:"browse_#{@mode}")
    @scope = current_browse_scope
    @frame_partial = "library/listing"
    render_frame_or_page
  end

  def rescan
    LibraryScanJob.perform_later
    toast("Library rescan started.")
  end

  private

  # YouTube-only deployment: the tab is gone, so this can only be reached by a
  # stale bookmark or a shared link. Root answers a turbo-frame request with the
  # same `search_results` frame, so the redirect works from inside the frame too.
  def require_local_library
    return if local_library?

    if request.get?
      redirect_to root_path, alert: "No local library on this box — YouTube only."
    else
      toast("No local library on this box — YouTube only.", type: :alert)
    end
  end

  # No listing of its own — 22k rows is not a browse. It exists so a search can be
  # aimed at every song at once, which is what the other modes deliberately are not.
  def browse_all
    @entries = []
    @breadcrumb = [crumb("All songs", nil)]
  end

  def browse_albums
    lib = LocalLibrary.new
    if params.key?(:album)
      @tracks = lib.album_tracks(params[:artist], params[:album])
      @add = { url: add_album_queue_items_path, params: { artist: params[:artist], album: params[:album] } }
      @breadcrumb = [crumb("Albums", browse: "albums"),
                     crumb(params[:album].presence || "Unknown album", nil)]
    else
      @entries = paginate(lib.all_albums)
      @breadcrumb = [crumb("Albums", nil)]
    end
  end

  def browse_artists
    lib = LocalLibrary.new
    if params.key?(:album)
      @tracks = lib.album_tracks(params[:artist], params[:album])
      @add = { url: add_album_queue_items_path, params: { artist: params[:artist], album: params[:album] } }
      @breadcrumb = [crumb("Artists", browse: "artists"),
                     crumb(params[:artist], browse: "artists", artist: params[:artist]),
                     crumb(params[:album].presence || "Unknown album", nil)]
    elsif params.key?(:artist)
      @entries = lib.albums(params[:artist])
      @breadcrumb = [crumb("Artists", browse: "artists"), crumb(params[:artist], nil)]
    else
      @entries = paginate(lib.artists)
      @breadcrumb = [crumb("Artists", nil)]
    end
  end

  def browse_folders
    lib = LocalLibrary.new
    rel = lib.normalize_rel(params[:path])
    @entries, @tracks = lib.folder(rel)
    @add = { url: add_folder_queue_items_path, params: { path: rel } } if rel.present?
    @breadcrumb = folder_breadcrumb(rel)
  end

  # Only the flat top-level listings (every artist, every album) get paged;
  # drilled-in views are small by construction.
  def paginate(entries)
    pager = AlphaPager.new(entries)
    @pages = pager.pages
    @current_page = pager.page_for(params[:page])
    @current_page ? @current_page.entries : entries
  end

  def crumb(label, params) = { label: label, params: params }

  def folder_breadcrumb(rel)
    segments = rel.to_s.split("/")
    crumbs = [crumb("Folders", rel.present? ? { browse: "folders" } : nil)]
    segments.each_with_index do |seg, i|
      path = segments[0..i].join("/")
      last = i == segments.size - 1
      crumbs << crumb(seg, last ? nil : { browse: "folders", path: path })
    end
    crumbs
  end
end
