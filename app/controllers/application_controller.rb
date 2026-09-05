class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_nick, :current_user, :signed_in?, :current_browse_scope, :local_library?,
                :admin?

  private

  # Is there a local library at all? Blank music_dir = YouTube-only deployment.
  def local_library?
    PartyConfig.local_library?
  end

  # Whoever is using PartyConfig.admin_nick: may seek, and may skip alone.
  def admin?
    PartyConfig.admin?(current_nick)
  end

  # Self-set nickname, stored in a signed cookie. No password — trusted LAN.
  def current_nick
    cookies.signed[:nick].presence
  end

  def current_user
    User.find_by(nick: current_nick) if current_nick
  end

  # The active library-browse scope (derived from params the browse links and the
  # search form both carry), or nil for an unscoped/global search. When present,
  # search is limited to this slice of the local library. `nav` reconstructs the
  # params needed to return to the matching browse view.
  def current_browse_scope
    browse = params[:browse].presence
    return nil unless browse
    # Without a library, every browse scope but history is meaningless. Dropping
    # it here (rather than trusting the links to be gone) means a bookmarked
    # ?browse=albums URL degrades to a plain search instead of silently scoping
    # it to a library that isn't there.
    return nil if browse != "history" && !local_library?

    if browse == "history"
      { browse: "history", label: "History" }
    elsif browse == "all"
      { browse: "all", label: "All songs", nav: { browse: "all" } }
    elsif browse == "albums"
      artist = params[:artist].presence
      album  = params[:album].presence
      if album
        { browse: "albums", artist: artist, album: album, label: album,
          nav: { browse: "albums", artist: artist, album: album } }
      else
        { browse: "albums", label: "Albums", nav: { browse: "albums" } }
      end
    elsif browse == "folders"
      path = params[:path].to_s
      { browse: "folders", path: path, label: path.presence || "Local library",
        nav: { browse: "folders", path: path } }
    else
      artist = params[:artist].presence
      album  = params[:album].presence
      if artist && album
        { browse: "artists", artist: artist, album: album, label: "#{artist} · #{album}",
          nav: { browse: "artists", artist: artist, album: album } }
      elsif artist
        { browse: "artists", artist: artist, label: artist, nav: { browse: "artists", artist: artist } }
      else
        { browse: "artists", label: "Local library", nav: { browse: "artists" } }
      end
    end
  end

  def signed_in?
    current_nick.present?
  end

  def require_nick
    redirect_to(root_path, alert: "Pick a nickname first.") unless signed_in?
  end

  # What a full page render needs. No queue: it is a turbo-frame that fetches
  # itself (PartyController), so browsing costs no queue query. The player stays
  # because <title> is server-rendered for the first paint.
  def load_app_shell
    User.touch_nick(current_nick) if signed_in?
    @player = PlayerState.instance
    @current_item = @player.current_queue_item
  end

  # Browse/search endpoints render into the search_results frame. A non-frame GET
  # of the same URL renders the WHOLE app with that content already in the frame.
  # That happens on a deep link, a reload, a history restore — and on every Turbo
  # morph refresh, which re-fetches whatever URL the browser is currently on. So
  # keeping browse state in the URL is what makes the frame survive a broadcast;
  # it is not decoration.
  def render_frame_or_page
    return if turbo_frame_request?

    load_app_shell
    render template: "party/index"
  end

  def toast(message, type: :notice)
    render turbo_stream: turbo_stream.append(
      "toasts", partial: "shared/toast", locals: { message: message, type: type }
    )
  end
end
