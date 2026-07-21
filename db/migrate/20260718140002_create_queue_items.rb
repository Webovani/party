class CreateQueueItems < ActiveRecord::Migration[8.1]
  def change
    create_table :queue_items do |t|
      t.references :track, null: false, foreign_key: true
      t.float   :position, null: false               # float rank for cheap reorder
      t.string  :queued_by, null: false              # nick
      t.string  :state, null: false, default: "queued" # queued|playing|played|skipped
      t.timestamps
    end

    add_index :queue_items, :position
    add_index :queue_items, :state
  end
end
