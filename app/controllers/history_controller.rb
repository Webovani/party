class HistoryController < ApplicationController
  before_action :require_nick

  LIMIT = 100

  # Distinct tracks that have been played or skipped, most-recently-played first.
  def index
    # Local rows are hidden when there is no library: they cannot be re-added
    # (Enqueuer refuses them), so listing them would only offer a button that
    # always fails. Old plays from before the library was switched off — or from
    # a drive that used to be mounted here — are exactly that case.
    scope = local_library? ? Track.all : Track.youtube
    @tracks = scope
              .joins(:queue_items)
              .where(queue_items: { state: %w[played skipped] })
              .select("tracks.*, max(queue_items.updated_at) AS last_played")
              .group("tracks.id")
              .order("last_played DESC")
              .limit(LIMIT)
    @scope = { browse: "history", label: "History" }
    @frame_partial = "history/listing"
    render_frame_or_page
  end
end
