# When the player started this item. Null for rows that played before this column.
class AddStartedAtToQueueItems < ActiveRecord::Migration[8.1]
  def change
    add_column :queue_items, :started_at, :datetime
  end
end
