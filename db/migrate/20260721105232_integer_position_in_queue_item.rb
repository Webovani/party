class IntegerPositionInQueueItem < ActiveRecord::Migration[8.1]
  def change
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE queue_items SET position = position / 1024.0
        SQL
        change_column :queue_items, :position, :bigint, :null => false
      end
      dir.down do
        change_column :queue_items, :position, :float, :null => false
        execute <<-SQL
          UPDATE queue_items SET position = position * 1024.0
        SQL
      end
    end
  end
end
