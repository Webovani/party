require "csv"

# Every play and skip as CSV, oldest first.
#
# ended_at is the item's last state change: when the track finished, or when it
# was cut. played_ms is wall clock across that, pauses included, and blank for
# rows that played before started_at existed.
class HistoryExport
  HEADERS = %w[
    started_at ended_at played_ms state title artist album duration duration_ms
    queued_by added_at source link filler
  ].freeze

  def self.filename(now = Time.current)
    "party-history-#{now.strftime('%Y%m%d-%H%M')}.csv"
  end

  def to_csv
    CSV.generate do |csv|
      csv << HEADERS
      items.each { |item| csv << row(item) }
    end
  end

  private

  # Not find_each: it ignores the order, and this is party-sized data.
  def items
    QueueItem.where(state: %w[played skipped]).includes(:track).order(:updated_at, :id)
  end

  def row(item)
    track = item.track

    [
      time(item.started_at), time(item.updated_at), played_ms(item), item.state,
      track.title, track.artist, track.album,
      duration(track.duration_ms), track.duration_ms, item.queued_by,
      time(item.created_at), track.source, link(track), item.filler
    ]
  end

  # Local rows stay in with no library: a record of what happened, not a re-add list.
  def link(track) = track.youtube_url || track.local_path

  def time(timestamp) = timestamp&.in_time_zone&.strftime("%Y-%m-%d %H:%M:%S")

  def played_ms(item)
    return nil if item.started_at.nil?

    ((item.updated_at - item.started_at) * 1000).round
  end

  def duration(ms)
    return nil if ms.blank?

    total = ms.to_i / 1000
    format("%d:%02d", total / 60, total % 60)
  end
end
