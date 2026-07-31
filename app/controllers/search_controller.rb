class SearchController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @scope = current_browse_scope

    # Clearing the query while scoped returns to that view (browse or history);
    # unscoped, it goes home — so an empty search never lands in history as a
    # bare /search?q= entry to back through.
    return redirect_to(scope_return_path(@scope)) if @query.blank? && @scope
    return redirect_to(root_path) if @query.blank?

    # A scoped search answers with the collections that match as well as the songs
    # inside them: searching "abba" under Albums should surface the ABBA albums,
    # not only the individual tracks.
    @entries = @scope ? LocalLibrary.new.search_entries(@scope, @query) : []

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

    @frame_partial = "search/frame"
    render_frame_or_page
  end

  private

  # Search within the active scope, preserving each track's real source.
  def scoped_results(scope, query)
    base = scope[:browse] == "history" ? Track.history : LocalLibrary.new.scope_base(scope)
    base.matching(query).limit(50).map(&:to_search_result)
  end

  def scope_return_path(scope)
    scope[:browse] == "history" ? history_path : library_path(scope[:nav])
  end
end
