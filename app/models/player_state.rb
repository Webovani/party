class PlayerState < ApplicationRecord
  STATUSES = %w[stopped playing paused].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :volume, numericality: { in: 0..100 }

  # Singleton row — there is exactly one player.
  def self.instance
    first || create!
  end

  def current_queue_item
    return nil if current_queue_item_id.blank?

    QueueItem.find_by(id: current_queue_item_id)
  end

  def current_track
    current_queue_item&.track
  end

  def stopped? = status == "stopped"
  def playing? = status == "playing"
  def paused?  = status == "paused"
end
