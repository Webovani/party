class HistoryController < ApplicationController
  before_action :require_nick

  LIMIT = 100

  # Distinct tracks that have been played or skipped, most-recently-played first.
  def index
    return redirect_to(root_path) unless turbo_frame_request?

    @tracks = Track
              .joins(:queue_items)
              .where(queue_items: { state: %w[played skipped] })
              .select("tracks.*, max(queue_items.updated_at) AS last_played")
              .group("tracks.id")
              .order("last_played DESC")
              .limit(LIMIT)
  end
end
