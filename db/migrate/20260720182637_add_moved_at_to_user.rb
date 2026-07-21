class AddMovedAtToUser < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :moved_at, :datetime
  end
end
