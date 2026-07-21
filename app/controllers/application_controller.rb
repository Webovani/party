class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_nick, :current_user, :signed_in?, :current_browse_scope

  private

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

    if browse == "history"
      { browse: "history", label: "History" }
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

  def toast(message, type: :notice)
    render turbo_stream: turbo_stream.append(
      "toasts", partial: "shared/toast", locals: { message: message, type: type }
    )
  end
end
