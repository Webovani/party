class AddFillerToQueueItems < ActiveRecord::Migration[8.1]
  # A long track (a DJ mix) added to fill lazy moments: it sorts behind everything
  # else and is interrupted the moment anyone queues a real song, resuming later
  # from where it stopped.
  def change
    add_column :queue_items, :filler, :boolean, default: false, null: false
    add_column :queue_items, :resume_position_ms, :integer, default: 0, null: false
    add_index :queue_items, [:filler, :position]
  end
end
