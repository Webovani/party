class HistoryController < ApplicationController
  before_action :require_nick

  LIMIT = 100

  # Distinct tracks that have been played or skipped, most-recently-played first.
  def index
    @tracks = Track
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
