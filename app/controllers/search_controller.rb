class SearchController < ApplicationController
  def index
    # Search results are only meant to load into the frame on the main page.
    # A direct (full-page) visit should land on the app, not the bare frame.
    return redirect_to(root_path(q: params[:q])) unless turbo_frame_request?

    @query = params[:q].to_s.strip
    @scope = current_browse_scope

    # Clearing the query while scoped returns to that view (browse or history).
    return redirect_to(scope_return_path(@scope)) if @query.blank? && @scope

    @sections =
      if @query.blank?
        []
      elsif @scope
        [{ source: @scope[:browse], results: scoped_results(@scope, @query) }]
      elsif (video = Sources::Youtube.new.resolve_url(@query))
        # Pasted a YouTube URL — show just that video, ready to add.
        [{ source: "youtube", results: [video] }]
      else
        Sources::Registry.search_all(@query, limit: 25)
      end
  end

  private

  # Search within the active scope, preserving each track's real source.
  def scoped_results(scope, query)
    base = scope[:browse] == "history" ? Track.history : LocalLibrary.new.scope_base(scope)
    base.search(query).limit(50).map(&:to_search_result)
  end

  def scope_return_path(scope)
    scope[:browse] == "history" ? history_path : library_path(scope[:nav])
  end
end
