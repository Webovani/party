class LibraryController < ApplicationController
  before_action :require_nick

  def index
    return redirect_to(root_path) unless turbo_frame_request?

    @library_total = Track.local.count
    @mode = params[:browse] == "folders" ? :folders : :artists
    @mode == :folders ? browse_folders : browse_artists
  end

  def rescan
    LibraryScanJob.perform_later
    toast("Library rescan started.")
  end

  private

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
      @entries = lib.artists
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
