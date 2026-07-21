class CreatePlayerStates < ActiveRecord::Migration[8.1]
  def change
    create_table :player_states do |t|
      t.string  :status, null: false, default: "stopped" # stopped|playing|paused
      t.bigint  :current_queue_item_id                    # not FK: item may be pruned
      t.integer :position_ms, null: false, default: 0
      t.integer :duration_ms, null: false, default: 0
      t.integer :volume, null: false, default: 80
      t.timestamps
    end
  end
end
